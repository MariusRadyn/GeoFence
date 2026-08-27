
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/iot_data_logs_page.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class IotDataPage extends StatefulWidget {
  const IotDataPage({super.key});

  @override
  State<IotDataPage> createState() => IotDataPageState();
}

class IotDataPageState extends State<IotDataPage> with TickerProviderStateMixin {
  late SettingsService settings;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final nrFormatter = NumberFormat('0.00', 'en_US');
  DateTime _selectedDateFrom =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDateTo = DateTime.now();

  TabController? _baseTabController;

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

  /// Same broad query as the summary list; [IotDataLogsPage] filters by monitor.
  Stream<QuerySnapshot> _iotDataStreamForMonitor(
    DateTime from,
    DateTime to,
    MonitorSettings monitor,
  ) {
    if (monitor.monDocId.isEmpty) {
      return const Stream.empty();
    }
    return _iotDataStream(from, to);
  }

  @override
  void initState() {
    super.initState();
    _loadSavedDateRange();
  }

  @override
  void dispose() {
    _baseTabController?.dispose();
    super.dispose();
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

  void _updateBaseTabs(int length) {
    if (length == 0) {
      _baseTabController?.dispose();
      _baseTabController = null;
      return;
    }

    if (_baseTabController == null || _baseTabController!.length != length) {
      final oldIndex = _baseTabController?.index ?? 0;
      _baseTabController?.dispose();
      _baseTabController = TabController(
        length: length,
        vsync: this,
        initialIndex: oldIndex.clamp(0, length - 1),
      );
    }
  }

  void createSummaryWheel(
    QueryDocumentSnapshot doc,
    MonitorSettings monitor,
    Map<String, Map<String, dynamic>> summaryWheel,
  ) {
    double dist = 0.0;
    num lines = 0;
    num ticks = 0;

    try {
      lines = doc.get(fireIotLines) ?? 0;
      ticks = doc.get(fireIotTicks) ?? 0;
      dist = lines * (ticks / monitor.ticksPerM);
    } catch (e) {
      printDebugMsg('$e');
    }

    if (!summaryWheel.containsKey(monitor.monDocId)) {
      summaryWheel[monitor.monDocId] = {
        'name': monitor.monitorName,
        'totalDistance': 0.0,
        'totalLines': 0,
        'logCount': 0,
        'image': monitor.imageURL ?? "",
        'imageFilename': monitor.imageFilename ?? "",
      };
    }

    summaryWheel[monitor.monDocId]!['totalDistance'] += (dist);
    summaryWheel[monitor.monDocId]!['totalLines'] += lines;
    summaryWheel[monitor.monDocId]!['logCount'] += 1;
  }

  Widget _buildWheelMonitorLog(
    List<MonitorSettings> lstMonitorSettings,
    DateTime fromDate,
    DateTime toDate,
    Map<String, Map<String, dynamic>> summaryWheel,
  ) {
    var summaryList = summaryWheel.values.toList();

    return Column(
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
                orElse: () => lstMonitorSettings.first,
              );

              final displayUrl = resolvedNetworkImageUrl(
                image,
                version: imageFilename,
              );

              return Column(
                children: [
                  SizedBox(height: 20),
                  MyTextTileWithEditDelete(
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
                    subtext: 'Logs: ${iotSummary['logCount']}\n'
                        'Lines: ${iotSummary['totalLines']}\n'
                        'Total: ${iotSummary['totalDistance'].toInt()} m',
                    headerColor: Colors.white,
                    textColor: Colors.grey,
                    backgroundColor: colorAppBar,
                    onTapTile: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => IotDataLogsPage(
                            monitor: actualMonitor,
                            streamIotData: _iotDataStreamForMonitor(
                              fromDate,
                              toDate,
                              actualMonitor,
                            ),
                            userDocId: FirebaseAuth.instance.currentUser?.uid,
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 1),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelector() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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

  Widget _buildBody(
    AsyncSnapshot<QuerySnapshot<Object?>> iotSnapshot,
    DateTime fromDate,
    DateTime toDate,
    String baseStationDocId,
  ) {
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

    if (iotSnapshot.connectionState == ConnectionState.waiting) {
      return Center(child: myProgressCircle());
    }

    if (!iotSnapshot.hasData || iotSnapshot.data!.docs.isEmpty) {
      return const Column(
        children: [
          Expanded(
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

    final lstMonitorSettings = context
        .watch<MonitorSettingsService>()
        .getMonitorsForBase(baseStationDocId);
    if (lstMonitorSettings.isEmpty) {
      return const Center(
        child: MyText(
          text: "No iOT Monitors for this base",
          color: Colors.grey,
        ),
      );
    }

    final monIds = lstMonitorSettings.map((m) => m.monDocId).toSet();
    final summaryWheel = <String, Map<String, dynamic>>{};

    for (var doc in iotSnapshot.data!.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      final monId = '${data?[fireIotMonDocId] ?? ''}';
      if (monId.isEmpty || !monIds.contains(monId)) continue;

      // Prefer docs that belong to this base (field or path); allow legacy
      // docs with no baseStationDocId so migrated users still see history.
      final docBaseId = '${data?[fireIotBaseStationDocId] ?? ''}';
      final pathBaseId = baseStationDocIdFromMonitorPath(doc.reference.path);
      if (docBaseId.isNotEmpty && docBaseId != baseStationDocId) continue;
      if (pathBaseId != null &&
          pathBaseId.isNotEmpty &&
          pathBaseId != baseStationDocId) {
        continue;
      }

      MonitorSettings? monitor;
      try {
        monitor = lstMonitorSettings.firstWhere((x) => x.monDocId == monId);
      } catch (e) {
        continue;
      }

      if (monitor.monitorType == monitorTypeWheel) {
        createSummaryWheel(doc, monitor, summaryWheel);
      }
    }

    if (summaryWheel.isNotEmpty) {
      return _buildWheelMonitorLog(
        lstMonitorSettings,
        fromDate,
        toDate,
        summaryWheel,
      );
    }
    return const Center(
      child: MyText(
        text: "No Data",
        color: Colors.grey,
      ),
    );
  }

  Widget _buildDateTabsForBase(BaseStationData base) {
    final DateTime today = DateTime.now();

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: colorAppBar,
            child: const TabBar(
              labelColor: Colors.white,
              indicatorColor: colorOrange,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: "Today"),
                Tab(text: "Month"),
                Tab(text: "By Date"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                Container(
                  color: colorAppBackground,
                  child: StreamBuilder<QuerySnapshot>(
                    key: ValueKey('iot-data-today-${base.docId}'),
                    stream: _iotDataStream(today, today),
                    builder: (context, iotSnapshot) => _buildBody(
                      iotSnapshot,
                      today,
                      today,
                      base.docId,
                    ),
                  ),
                ),
                Container(
                  color: colorAppBackground,
                  child: StreamBuilder<QuerySnapshot>(
                    key: ValueKey('iot-data-month-${base.docId}'),
                    stream: _iotDataStream(
                      DateTime(today.year, today.month, 1),
                      today,
                    ),
                    builder: (context, iotSnapshot) => _buildBody(
                      iotSnapshot,
                      DateTime(today.year, today.month, 1),
                      today,
                      base.docId,
                    ),
                  ),
                ),
                Container(
                  color: colorAppBackground,
                  child: Column(
                    children: [
                      _buildDateSelector(),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          key: ValueKey(
                            'iot-data-range-${base.docId}-'
                            '${_selectedDateFrom.year}-${_selectedDateFrom.month}-${_selectedDateFrom.day}-'
                            '${_selectedDateTo.year}-${_selectedDateTo.month}-${_selectedDateTo.day}',
                          ),
                          stream: _iotDataStream(
                            _selectedDateFrom,
                            _selectedDateTo,
                          ),
                          builder: (context, iotSnapshot) => _buildBody(
                            iotSnapshot,
                            _selectedDateFrom,
                            _selectedDateTo,
                            base.docId,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BaseStationService, MonitorSettingsService>(
      builder: (context, baseService, monitors, _) {
        if (baseService.isLoading || monitors.isLoading) {
          return Scaffold(
            backgroundColor: colorAppBackground,
            appBar: AppBar(
              title: myAppbarTitle('iOT Data'),
              backgroundColor: colorAppBar,
              foregroundColor: Colors.white,
            ),
            body: Center(child: myProgressCircle()),
          );
        }

        _updateBaseTabs(baseService.lstBaseStations.length);

        return Scaffold(
          backgroundColor: colorAppBackground,
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
            bottom: baseService.lstBaseStations.isNotEmpty
                ? TabBar(
                    controller: _baseTabController,
                    isScrollable: true,
                    labelColor: Colors.white,
                    indicatorColor: Colors.blueAccent,
                    unselectedLabelColor: Colors.grey,
                    tabs: baseService.lstBaseStations
                        .map((b) => Tab(text: b.baseName))
                        .toList(),
                  )
                : null,
          ),
          body: baseService.lstBaseStations.isEmpty
              ? myCenterMsg(
                  'No Base Stations. Add one on the Base Stations page.',
                )
              : TabBarView(
                  controller: _baseTabController,
                  children: baseService.lstBaseStations
                      .map(_buildDateTabsForBase)
                      .toList(),
                ),
        );
      },
    );
  }
}
