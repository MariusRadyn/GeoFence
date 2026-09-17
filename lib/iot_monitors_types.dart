//import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/app_flavor.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// Vehicle
class IotVehicleType extends StatefulWidget {
  final MonitorSettings monitorData;
  final Function(String) onChangedVehicleName;
  final Function(String) onChangedFuelConsumption;
  final Function(String) onChangedReg;
  final Function(BluetoothDevice?) onChangedBluetooth;
  final List<BluetoothDevice> lstPairedDevices;

  const IotVehicleType({
    super.key,
    required this.monitorData,
    required this.onChangedVehicleName,
    required this.onChangedFuelConsumption,
    required this.onChangedReg,
    required this.lstPairedDevices,
    required this.onChangedBluetooth
  });

  @override
  State<IotVehicleType> createState() => _IotVehicleTypeState();
}
class _IotVehicleTypeState extends State<IotVehicleType> {
  late final TextEditingController _controllerName;
  late final TextEditingController _controllerFuel;
  late final TextEditingController _controllerReg;
  late final FocusNode _focusNodeName;
  late final FocusNode _focusNodeFuel;
  late final FocusNode _focusNodeReg;

  @override
  void initState() {
    super.initState();
    _controllerName =
        TextEditingController(text: widget.monitorData.monitorName);
    _controllerFuel = TextEditingController(
        text: widget.monitorData.fuelConsumption.toString());
    _controllerReg = TextEditingController(text: widget.monitorData.reg);

    _focusNodeName = FocusNode();
    _focusNodeFuel = FocusNode();
    _focusNodeReg = FocusNode();

    _focusNodeName
        .addListener(() => _handleFocusChange(_focusNodeName, 'name'));
    _focusNodeFuel
        .addListener(() => _handleFocusChange(_focusNodeFuel, 'fuel'));
    _focusNodeReg
        .addListener(() => _handleFocusChange(_focusNodeReg, 'reg'));
  }

  @override
  void didUpdateWidget(covariant IotVehicleType oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_focusNodeName.hasFocus &&
        _controllerName.text != widget.monitorData.monitorName) {
      _controllerName.text = widget.monitorData.monitorName;
    }
    if (!_focusNodeFuel.hasFocus &&
        _controllerFuel.text !=
            widget.monitorData.fuelConsumption.toString()) {
      _controllerFuel.text = widget.monitorData.fuelConsumption.toString();
    }
    if (!_focusNodeReg.hasFocus &&
        _controllerReg.text != widget.monitorData.reg) {
      _controllerReg.text = widget.monitorData.reg;
    }
  }

  @override
  void dispose() {
    _controllerName.dispose();
    _controllerFuel.dispose();
    _controllerReg.dispose();
    _focusNodeName.dispose();
    _focusNodeFuel.dispose();
    _focusNodeReg.dispose();
    super.dispose();
  }

  void _handleFocusChange(FocusNode node, String field) {
    if (node.hasFocus) return;

    switch (field) {
      case 'name':
        widget.onChangedVehicleName(_controllerName.text);
        break;
      case 'fuel':
        widget.onChangedFuelConsumption(_controllerFuel.text);
        break;
      case 'reg':
        widget.onChangedReg(_controllerReg.text);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        // Vehicle Info
        Padding(
          padding: const EdgeInsets.fromLTRB(8,0,8,5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Vehicle Name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: MyTextFormField(
                  focusNode: _focusNodeName,
                  backgroundColor: colorAppBackground,
                  foregroundColor: Colors.white,
                  controller: _controllerName,
                  hintText: "Enter value here",
                  labelText: "Vehicle Name",
                  onFieldSubmitted: widget.onChangedVehicleName,
               ),
              ),

              // FuelConsumption
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: MyTextFormField(
                  focusNode: _focusNodeFuel,
                  backgroundColor: colorAppBackground,
                  foregroundColor: Colors.white,
                  controller: _controllerFuel,
                  hintText: "Enter value here",
                  labelText: "Consumption",
                  suffix: "l/100Km",
                  inputType: TextInputType.number,
                  onFieldSubmitted: widget.onChangedFuelConsumption,
                ),
              ),

              // Reg Number
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: MyTextFormField(
                  focusNode: _focusNodeReg,
                  backgroundColor: colorAppBackground,
                  foregroundColor: Colors.white,
                  controller: _controllerReg,
                  hintText: "Enter value here",
                  labelText: "Registration Number",
                  onFieldSubmitted: widget.onChangedReg,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 10),

        // Vehicle ID Header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: MyTextHeader(
            text:'Vehicle ID',
            color: Colors.white,
            fontsize: 16,
          ),
        ),

        SizedBox(height: 5),

        if (AppConfig.enableBluetooth) ...[
          // Help text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Text('Use bluetooth connection in the monitor to get monitor ID. '
                'Select which bluetooth connection to use in the monitor. '
                'If the list is empty you need to pair to a bluetooth device first. '
                'The list is of paired devices, NOT connected devices ',
              softWrap: true,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.white
              ),
            ),
          ),

          SizedBox(height: 10),

          // Test Bluetooth
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15.0),
            child: GestureDetector(
              child: Text("Test Bluetooth Connection",
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 14,
                ),
              ),

              onTap: (){
                //testBluetooth();
              },
            ),
          ),

          SizedBox(height: 5),

          // Select Bluetooth
          Padding( padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 20),
            child: Theme(
              data: Theme.of(context).copyWith(canvasColor: colorAppTitle),
              child: DropdownButtonFormField<BluetoothDevice>(
                initialValue: (() {

                  // Find the matching paired device
                  return widget.lstPairedDevices.firstWhereOrNull(
                        (d) => d.remoteId.toString() == widget.monitorData.bluetoothMac,
                  );
                })(),

                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  isDense: false,
                  labelText: 'Select Bluetooth',
                  labelStyle: TextStyle(color: Colors.grey),
                  fillColor: colorAppBackground,
                  filled: true,
                  prefixIcon: const Icon(
                    Icons.bluetooth,
                    color: Colors.blueAccent,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  //contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
                hint: Text(widget.lstPairedDevices.isEmpty ? 'No paired devices' : 'Choose a paired device',
                  style: TextStyle(color: Colors.grey),
                ),
                items: widget.lstPairedDevices.map((BluetoothDevice device) {
                  return DropdownMenuItem<BluetoothDevice>(
                    value: device,
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              device.platformName.isNotEmpty
                                  ? device.platformName
                                  : 'Unknown Device',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: widget.onChangedBluetooth,
                isExpanded: true,
              ),
            ),
          ),
        ],

      ],
    );
  }
}

// Wheel
class IotDistanceWheelType extends StatefulWidget {
  final MonitorSettings monitorData;
  final Function(String) onChangedName;
  final Function(String) onChangedTicksPerM;
  final Function(String) onChangedMonId;
  final Function() onTapPair;
  final Function() onTapSendWifi;
  final Function() onTapFind;
  final Function() onTapSyncTicksPerM;
  final Function() onTapConnect;
  final Function() onTapCalibrate;

  const IotDistanceWheelType({
    super.key,
    required this.monitorData,
    required this.onChangedName,
    required this.onChangedTicksPerM,
    required this.onChangedMonId,
    required this.onTapPair,
    required this.onTapSendWifi,
    required this.onTapFind,
    required this.onTapSyncTicksPerM,
    required this.onTapConnect,
    required this.onTapCalibrate,
  });

  @override
  State<IotDistanceWheelType> createState() => IotDistanceWheelTypeState();
}
class IotDistanceWheelTypeState extends State<IotDistanceWheelType> {
  late SettingsService settingService;
  late final TextEditingController _controllerName;
  late final TextEditingController _controllerId;
  late final TextEditingController _controllerTicksPerM;
  late final TextEditingController _controllerDistance;
  late final TextEditingController _controllerWheelTicks;
  late final TextEditingController _controllerCalDistance;
  late FocusNode _focusNodeName;
  late FocusNode _focusNodeID;
  late FocusNode _focusNodeTicksPerM;
  late FocusNode _focusNodeCalDistance;
  bool _pairButtonPressed = false;
  bool _wifiButtonPressed = false;
  bool _findButtonPressed = false;
  bool _syncButtonPressed = false;
  bool _calibrateButtonPressed = false;
  bool _connectButtonPressed = false;
  bool _cancellingSubscription = false;
  
  Color colorSetupTile = colorAppBackground;
  Color colorCalibrateTile = colorAppBackground;
  Color colorLiveTile = colorAppBackground;
  
  @override
  void initState() {
    super.initState();
     _controllerId = TextEditingController(text: widget.monitorData.monitorId);
     _controllerName = TextEditingController(text: widget.monitorData.monitorName);
     _controllerTicksPerM = TextEditingController(text: widget.monitorData.ticksPerM.toString());
     _controllerDistance = TextEditingController(text: widget.monitorData.wheelDistance.toString());
     _controllerWheelTicks = TextEditingController(text: widget.monitorData.wheelTicks.toString());
     _controllerCalDistance = TextEditingController(text: widget.monitorData.calibrationDistance.toString());

    _focusNodeName = FocusNode();
    _focusNodeID = FocusNode();
    _focusNodeTicksPerM = FocusNode();
    _focusNodeCalDistance = FocusNode();

    // Add listeners to trigger save on focus loss
    _focusNodeName.addListener(() => _handleFocusChange(_focusNodeName, 'name'));
    _focusNodeID.addListener(() => _handleFocusChange(_focusNodeID, 'id'));
    _focusNodeTicksPerM.addListener(() => _handleFocusChange(_focusNodeTicksPerM, 'ticksPerM'));
    _focusNodeCalDistance.addListener(() => _handleFocusChange(_focusNodeCalDistance, 'calDistance'));

    WidgetsBinding.instance.addPostFrameCallback((_) {
    });
  }

  Future<void> _animateTap(
    FutureOr<void> Function() action,
    void Function(bool) setPressed,
  ) async {
    setState(() => setPressed(true));
    try {
      await action();
    } finally {
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) setState(() => setPressed(false));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settingService = context.watch<SettingsService>();
    // Rebuild Connect/Disconnect label when live IoT connection changes.
    context.watch<MonitorSettingsService>();
  }

  @override
  void didUpdateWidget(covariant IotDistanceWheelType oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Keep text fields in sync when parent updates monitor data (e.g. pair/swap).
    if (_controllerId.text != widget.monitorData.monitorId) {
      _controllerId.text = widget.monitorData.monitorId;
    }
    if (!_focusNodeName.hasFocus &&
        _controllerName.text != widget.monitorData.monitorName) {
      _controllerName.text = widget.monitorData.monitorName;
    }
    if (!_focusNodeTicksPerM.hasFocus &&
        _controllerTicksPerM.text != widget.monitorData.ticksPerM.toString()) {
      _controllerTicksPerM.text = widget.monitorData.ticksPerM.toString();
    }
    if (!_focusNodeCalDistance.hasFocus &&
        _controllerCalDistance.text !=
            widget.monitorData.calibrationDistance.toString()) {
      _controllerCalDistance.text =
          widget.monitorData.calibrationDistance.toString();
    }
    if (_controllerDistance.text !=
        widget.monitorData.wheelDistance.toString()) {
      _controllerDistance.text = widget.monitorData.wheelDistance.toString();
    }
    if (_controllerWheelTicks.text !=
        widget.monitorData.wheelTicks.toString()) {
      _controllerWheelTicks.text = widget.monitorData.wheelTicks.toString();
    }
  }

  @override
  void dispose() {
    _controllerId.dispose();
    _controllerDistance.dispose();
    _controllerWheelTicks.dispose();
    _controllerName.dispose();
    _controllerTicksPerM.dispose();

    _focusNodeName.dispose();
    _focusNodeID.dispose();
    _focusNodeTicksPerM.dispose();
    _focusNodeCalDistance.dispose();

    super.dispose();
  }

  void _handleFocusChange(FocusNode node, String field) {
    if (!node.hasFocus) {
      if (field == 'ticksPerM') {
        widget.onChangedTicksPerM(_controllerTicksPerM.text);
        return;
      }

      setState(() {
        if (field == 'name') widget.monitorData.monitorName = _controllerName.text;
        if (field == 'id') widget.monitorData.monitorId = _controllerId.text;
        if (field == 'calDistance') widget.monitorData.calibrationDistance = int.parse(_controllerCalDistance.text);

        context.read<MonitorSettingsService>().save(widget.monitorData);
      });
    }
  }
  
  // Public methods for parent to update text Controllers
  void updateDistance(double value) {
    if (!mounted) return;
    setState(() {
      widget.monitorData.wheelDistance = value;
      _controllerDistance.text = value.toStringAsFixed(2);
    });
  }

  void updateTicks(int value) {
    if (!mounted) return;
    setState(() {
      widget.monitorData.wheelTicks = value;
      _controllerWheelTicks.text = value.toString();
    });
  }

  void updateLiveConnected(bool connected) {
    if (!mounted) return;
    setState(() {
      widget.monitorData.isConnectedToIot = connected;
      widget.monitorData.isConnectingToIot = false;
    });
  }
  void updateCalDistance(int value) {
    if (!mounted) return;
    _controllerCalDistance.text = value.toStringAsFixed(2);
  }

  bool _isActiveSubscription(Map<String, dynamic> data) {
    final status = (data['subscriptionStatus'] ?? '').toString().toLowerCase();
    if (status == 'cancelled' || status == 'canceled') return false;
    final token = (data['subscriptionToken'] ?? data['payfastToken'] ?? '')
        .toString()
        .trim();
    if (token.isNotEmpty) return true;
    if (data['hasSubscription'] == true) {
      final orderStatus = (data['status'] ?? '').toString();
      return orderStatus == 'paid' || orderStatus == 'shipped';
    }
    final monthly = (data['subscriptionMonthly'] is num)
        ? (data['subscriptionMonthly'] as num).toDouble()
        : double.tryParse('${data['subscriptionMonthly']}') ?? 0;
    return monthly > 0 &&
        ((data['status'] ?? '').toString() == 'paid' ||
            (data['status'] ?? '').toString() == 'shipped');
  }

  String _subscriptionLabel(Map<String, dynamic> data, String orderId) {
    final money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
    final monthly = (data['subscriptionMonthly'] is num)
        ? (data['subscriptionMonthly'] as num).toDouble()
        : double.tryParse('${data['subscriptionMonthly']}') ?? 0;
    final items = (data['items'] is List) ? (data['items'] as List) : const [];
    final names = items
        .map((e) => (e is Map ? e['name'] : null)?.toString())
        .whereType<String>()
        .where((n) => n.trim().isNotEmpty)
        .take(2)
        .join(', ');
    final shortId =
        orderId.length > 8 ? '${orderId.substring(0, 8)}…' : orderId;
    final amount = monthly > 0 ? '${money.format(monthly)}/mo' : 'Subscription';
    if (names.isEmpty) return '$amount · $shortId';
    return '$amount · $names';
  }

  Set<String> _tiedSubscriptionOrderIds(MonitorSettingsService monitors) {
    final tied = <String>{};
    final currentDoc = widget.monitorData.monDocId;
    for (final m in monitors.lstMonitors) {
      final orderId = m.subscriptionOrderId.trim();
      if (orderId.isEmpty) continue;
      if (m.monDocId == currentDoc) continue;
      tied.add(orderId);
    }
    return tied;
  }

  Future<void> _assignSubscription({
    required String orderId,
    required String token,
  }) async {
    setState(() {
      widget.monitorData.subscriptionOrderId = orderId;
      widget.monitorData.subscriptionToken = token;
    });
    await context.read<MonitorSettingsService>().save(widget.monitorData);
  }

  Future<void> _removeSubscription() async {
    setState(() {
      widget.monitorData.subscriptionOrderId = '';
      widget.monitorData.subscriptionToken = '';
    });
    await context.read<MonitorSettingsService>().save(widget.monitorData);
  }

  Future<void> _cancelLinkedSubscription() async {
    final orderId = widget.monitorData.subscriptionOrderId.trim();
    final token = widget.monitorData.subscriptionToken.trim();
    if (orderId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorAppBar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.blue, width: 2),
        ),
        title: const Text(
          'Cancel subscription?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          token.isEmpty
              ? 'This cancels recurring billing for this wheel.\n\n'
                  'The subscription will still be active until the last day of the month.\n\n'
                  'This cannot be undone from the app.'
              : 'This cancels recurring billing for this subscription.\n\n'
                  'The subscription will still be active until the last day of the month.\n\n'
                  'This cannot be undone from the app.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Cancel subscription'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancellingSubscription = true);
    try {
      final functions =
          FirebaseFunctions.instanceFor(region: cloudFunctionsRegion);
      await functions.httpsCallable('cancelPayfastSubscription').call({
        'orderId': orderId,
      });
      if (!mounted) return;
      await context
          .read<MonitorSettingsService>()
          .clearSubscriptionFromOrder(orderId);
      if (!mounted) return;
      setState(() {
        widget.monitorData.subscriptionOrderId = '';
        widget.monitorData.subscriptionToken = '';
      });
      MyGlobalMessage.show(
        'Subscription',
        'Subscription cancelled.',
        MyMessageType.success,
      );
    } catch (e) {
      final message = e is FirebaseFunctionsException
          ? (e.message?.trim().isNotEmpty == true ? e.message! : e.code)
          : e.toString();
      MyGlobalMessage.show('Cancel failed', message, MyMessageType.error);
    } finally {
      if (mounted) setState(() => _cancellingSubscription = false);
    }
  }

  Widget _buildSubscriptionPicker(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Text(
        'Sign in to link a subscription',
        style: TextStyle(color: Colors.white54, fontSize: 13),
      );
    }

    final ordersRef = FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid)
        .collection(collectionShopOrders);

    return Consumer<MonitorSettingsService>(
      builder: (context, monitors, _) {
        final tied = _tiedSubscriptionOrderIds(monitors);
        final selectedId = widget.monitorData.subscriptionOrderId.trim();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ordersRef.orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snap) {
            final options = <DropdownMenuItem<String>>[];
            final labels = <String, String>{};
            final tokens = <String, String>{};

            if (snap.hasData) {
              for (final doc in snap.data!.docs) {
                final data = doc.data();
                if (!_isActiveSubscription(data)) continue;
                final orderId = (data['orderId'] ?? doc.id).toString().trim();
                if (orderId.isEmpty) continue;
                final token =
                    (data['subscriptionToken'] ?? data['payfastToken'] ?? '')
                        .toString()
                        .trim();
                // Skip subscriptions already tied to another wheel.
                if (tied.contains(orderId) && orderId != selectedId) continue;
                labels[orderId] = _subscriptionLabel(data, orderId);
                tokens[orderId] = token;
                options.add(
                  DropdownMenuItem<String>(
                    value: orderId,
                    child: Text(
                      labels[orderId]!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                );
              }
            }

            // Keep current selection visible even if order docs failed to load.
            if (selectedId.isNotEmpty &&
                !options.any((e) => e.value == selectedId)) {
              final token = widget.monitorData.subscriptionToken.trim();
              final short = selectedId.length > 8
                  ? '${selectedId.substring(0, 8)}…'
                  : selectedId;
              labels[selectedId] = 'Linked · $short';
              tokens[selectedId] = token;
              options.insert(
                0,
                DropdownMenuItem<String>(
                  value: selectedId,
                  child: Text(
                    labels[selectedId]!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              );
            }

            final hasSelection = selectedId.isNotEmpty &&
                options.any((e) => e.value == selectedId);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subscription',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: colorSetupTile,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor: colorAppBar,
                            value: hasSelection ? selectedId : null,
                            hint: Text(
                              snap.connectionState == ConnectionState.waiting
                                  ? 'Loading subscriptions…'
                                  : options.isEmpty
                                      ? 'No available subscriptions'
                                      : 'Select subscription',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white70,
                            ),
                            items: options,
                            onChanged: options.isEmpty
                                ? null
                                : (value) async {
                                    if (value == null) return;
                                    await _assignSubscription(
                                      orderId: value,
                                      token: tokens[value] ?? '',
                                    );
                                  },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Remove subscription',
                      onPressed: hasSelection ? _removeSubscription : null,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: hasSelection
                            ? Colors.redAccent
                            : Colors.white24,
                      ),
                      icon: const Icon(Icons.link_off),
                    ),
                  ],
                ),
                if (hasSelection &&
                    widget.monitorData.subscriptionToken.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Token: ${widget.monitorData.subscriptionToken}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                if (hasSelection) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      onPressed: _cancellingSubscription
                          ? null
                          : _cancelLinkedSubscription,
                      child: _cancellingSubscription
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.redAccent,
                              ),
                            )
                          : const Text(
                              'Cancel subscription',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
       
        // Setup Tile ----------------------------------
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: colorSetupTile,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.grey,
                width: 0.5
                ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          child: 
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5 ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // Setup
                  Center(
                    child: MyText(
                      text: "Setup", 
                      fontsize: 18
                    ),
                  ),

                  SizedBox(height: 15),

                  // Instructions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: MyText(
                        fontsize: 14,
                        color: Colors.grey,
                        text:
                          '1. Only 1 wheel at a time can be in \'PAIR\' mode\n'
                          '2. On the wheel, press \'STOP\' 5 times\n'
                          '3. Allow wheel to connect to Base\n'
                          '4. Wait until LCD says \'Click PAIR in App\'\n'
                          '5. Click \'PAIR\'\n'
                          'WiFi: force base to push WiFi settings over Bluetooth\n',
                      ),
                     ),
                  ),
                  
                  // Monitor Info
                  Padding(
                    padding: const EdgeInsets.only(top: 10,left: 8, right: 8),
                    child: MyTextHeader(text:"Monitor Info"),
                  ),

                  // Subscription (active PayFast subscriptions not tied to another wheel)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 8, 15, 4),
                    child: _buildSubscriptionPicker(context),
                  ),

                  // Wheel Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: MyTextFormField(
                      focusNode: _focusNodeName,
                      backgroundColor: colorSetupTile,
                      foregroundColor: Colors.white,
                      controller: _controllerName,
                      hintText: "none",
                      labelText: "Wheel Name",
                      onFieldSubmitted: widget.onChangedName,
                    ),
                  ),
              
                  SizedBox(height: 5),
              
                  // ID + Scan Button
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: MyTextFormField(
                            focusNode: _focusNodeID,
                            backgroundColor: colorSetupTile,
                            foregroundColor: Colors.white,
                            controller: _controllerId,
                            hintText: "none",
                            labelText: "Monitor ID",
                            onFieldSubmitted: widget.onChangedMonId,
                          ),
                        ),
                      ),
              
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: animatedActionButton(
                          pressed: _pairButtonPressed,
                          onTap: () => _animateTap(
                            widget.onTapPair,
                            (v) => _pairButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.connected_tv,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? Colors.lightBlueAccent
                                    : Colors.grey ,
                              ),
                              const SizedBox(height: 10),
                              Text("Pair",
                                style: TextStyle(
                                    color: settingService.isBaseStationConnected
                                      ? Colors.white
                                      : Colors.grey
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: animatedActionButton(
                          pressed: _wifiButtonPressed,
                          onTap: () => _animateTap(
                            () {
                              final typed = _controllerId.text.trim();
                              if (typed.isNotEmpty) {
                                widget.monitorData.monitorId = typed;
                              }
                              return widget.onTapSendWifi();
                            },
                            (v) => _wifiButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.wifi,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Cred",
                                style: TextStyle(
                                  color: settingService.isBaseStationConnected
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: animatedActionButton(
                          pressed: _findButtonPressed,
                          onTap: () => _animateTap(
                            () {
                              // Flush ID text into the model before Find.
                              final typed = _controllerId.text.trim();
                              if (typed.isNotEmpty) {
                                widget.monitorData.monitorId = typed;
                              }
                              return widget.onTapFind();
                            },
                            (v) => _findButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.sensors,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Find",
                                style: TextStyle(
                                  color: settingService.isBaseStationConnected
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              
                  SizedBox(height: 5),
              
                  // Ticks per M + Sync
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: MyTextFormField(
                            focusNode: _focusNodeTicksPerM,
                            backgroundColor: colorSetupTile,
                            foregroundColor: Colors.white,
                            controller: _controllerTicksPerM,
                            hintText: "none",
                            labelText: "Ticks per Meter",
                            onFieldSubmitted: widget.onChangedTicksPerM,
                            inputType: TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: animatedActionButton(
                          pressed: _syncButtonPressed,
                          onTap: () => _animateTap(
                            () async {
                              final value = _controllerTicksPerM.text.trim();
                              if (value.isNotEmpty) {
                                await widget.onChangedTicksPerM(value);
                              }
                              return widget.onTapSyncTicksPerM();
                            },
                            (v) => _syncButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.sync,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Sync",
                                style: TextStyle(
                                  color: settingService.isBaseStationConnected
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 20,)
                ],
              ),
            ),  
          ),
        ),
        SizedBox(height: 20),
        
        // Calibrate Tile ------------------------------
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
             decoration: BoxDecoration(
                color: colorCalibrateTile,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.grey,
                  width: 0.5
                  ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // Calibrate Header
                  Center(
                    child: MyText(
                      text: "Calibrate", 
                      fontsize: 18
                    ),
                  ),

                  SizedBox(height: 15),

                  // Instructions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MyText(
                          fontsize: 14,
                          color: Colors.grey,
                          text:
                            '1. Enter the calibration distance\n'
                            '2. Pre measure this exact distance\n'
                            '3. On the wheel, press \'START\' 5 times\n'
                            '4. Check LCD if the wheel enters \'CALIBRATION\' mode\n'
                            '5. On the wheel, press \'START\'\n'
                            '6. Move the wheel the exact distance\n'
                            '7. On the wheel, press \'STOP\'\n'
                            '8. Take wheel back into WIFI range\n'
                            '9. In the App press \'CALIBRATE\'\n'    
                        ),     
                      ],
                    ),
                  ),

                  // Calibration Data Header
                  Padding(
                    padding: const EdgeInsets.only(top: 10,left: 8, right: 8),
                    child: MyTextHeader(text:"Calibration Data"),
                  ),

                  // Calibration Distance
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: MyTextFormField(
                            focusNode: _focusNodeCalDistance,
                            backgroundColor: colorCalibrateTile,
                            foregroundColor: Colors.white,
                            controller: _controllerCalDistance,
                            labelText: "Calibration Distance",
                          ),
                        ),
                      ),

                       Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 8.0),
                         child: animatedActionButton(
                          pressed: _calibrateButtonPressed,
                          onTap: () => _animateTap(
                            () async {
                              FocusScope.of(context).unfocus();
                              final text = _controllerCalDistance.text.trim();
                              final parsed = int.tryParse(text) ??
                                  double.tryParse(text)?.round();
                              if (parsed != null && parsed > 0) {
                                widget.monitorData.calibrationDistance = parsed;
                                await context
                                    .read<MonitorSettingsService>()
                                    .save(widget.monitorData);
                              }
                              await widget.onTapCalibrate();
                            },
                            (v) => _calibrateButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.online_prediction_sharp,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? widget.monitorData.isConnectedToIot
                                        ? Colors.greenAccent
                                        : Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Calibrate",
                                style: TextStyle(
                                  color: settingService.isBaseStationConnected
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                         ),
                       ),
                    
                    ],
                  ),
          
                  SizedBox(height: 10),

                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 20),
       
        // Live Mode Tile ------------------------------
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
             decoration: BoxDecoration(
                color: colorLiveTile,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.grey,
                  width: 0.5
                  ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // Live Monitor
                  Center(
                    child: MyText(
                      text: "Live Monitor", 
                      fontsize: 18
                    ),
                  ),
                  SizedBox(height: 15),

                  // Instructions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MyText(
                          fontsize: 14,
                          color: Colors.grey,
                          text:
                            '1. Press Connect or Disconnect for live monitor\n'
                            '2. Move the wheel\n'
                        ),     
                      ],
                    ),
                  ),
                   
                  // Live Monitor Header
                  Padding(
                    padding: const EdgeInsets.only(top: 10,left: 8, right: 8),
                    child: MyTextHeader(text:"Live Data"),
                  ),
                 
                  // Live Monitor Ticks / Distance / Connect Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: MyTextFormField(
                                backgroundColor: colorCalibrateTile,
                                foregroundColor: Colors.white,
                                controller: _controllerWheelTicks,
                                labelText: "Ticks",
                                isReadOnly: true,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: MyTextFormField(
                                backgroundColor: colorCalibrateTile,
                                foregroundColor: Colors.white,
                                controller: _controllerDistance,
                                labelText: "Distance",
                                isReadOnly: true,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Connect Button
                      Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 8.0),
                         child: animatedActionButton(
                          pressed: _connectButtonPressed,
                          onTap: () => _animateTap(
                            widget.onTapConnect,
                            (v) => _connectButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.online_prediction_sharp,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? widget.monitorData.isConnectedToIot
                                        ? Colors.greenAccent
                                        : Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                widget.monitorData.isConnectedToIot
                                    ? "Disconnect"
                                    : "Connect",
                                style: TextStyle(
                                  color: settingService.isBaseStationConnected
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                         ),
                       ),
                    
                    ],
                  ),
          
                  SizedBox(height: 10),

                ],
              ),
            ),
          ),
        )
      ],  
    );
    
  }
}
