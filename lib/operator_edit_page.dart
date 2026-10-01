import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/app_flavor.dart';
import 'package:geofence/iot_ble_operator_sync.dart';
import 'package:geofence/mqtt_service.dart';
import 'package:geofence/edit_profile_pic_page.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/utils.dart';
//import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class OperatorEditPage extends StatefulWidget {
  final OperatorData? operatorData;

  const OperatorEditPage({
    required this.operatorData,
    super.key
  });

  @override
  State<OperatorEditPage> createState() => OperatorEditPageState();
}
class OperatorEditPageState extends State<OperatorEditPage> {
  TextEditingController? _controllerName;
  TextEditingController? _controllerSurname;
  TextEditingController? _controllerTag;
  TextEditingController? _controllerRate;

  bool tagRequested = false;
  bool listenerStarted = false;
  bool _bleReadBusy = false;
  Timer? _timeout;
  bool _dialogScheduled = false; // prevents multiple registrations
  bool _dialogShown = false;     // prevents multiple dialogs
  StreamSubscription<String>? _mqttSubscription;

  late String oldName;
  late String oldSurname;

  late FocusNode _focusNodeName;
  late FocusNode _focusNodeSurname;
  late FocusNode _focusNodeRate;

  @override
  void initState() {
    super.initState();

    _controllerName = TextEditingController(text: widget.operatorData?.name ?? '');
    _controllerSurname = TextEditingController(text: widget.operatorData?.surname ?? '');
    _controllerTag = TextEditingController(text: widget.operatorData?.tagId ?? '');
    _controllerRate = TextEditingController(text: widget.operatorData?.rate.toString() ?? '0.0');

    _focusNodeName = FocusNode();
    _focusNodeSurname = FocusNode();
    _focusNodeRate = FocusNode();

    _focusNodeName.addListener(() => _handleFocusChange(_focusNodeName, 'name'));
    _focusNodeSurname.addListener(() => _handleFocusChange(_focusNodeSurname, 'surname'));
    _focusNodeRate.addListener(() => _handleFocusChange(_focusNodeRate, 'rate'));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      listenerStarted = false;
      _mqttStartListener();
    });
  }

  @override
  void dispose() {
    listenerStarted = false;
    tagRequested = false;
    _timeout?.cancel();

    _focusNodeName.dispose();
    _focusNodeSurname.dispose();

    _controllerName?.dispose();
    _controllerSurname?.dispose();
    _controllerTag?.dispose();

    _mqttSubscription?.cancel();

    super.dispose();
  }

  // Timers
  void _startTimeout(int sec) {
    _timeout?.cancel();
    _dialogScheduled = false;
    _dialogShown = false;

    _timeout = Timer(Duration(seconds: sec), () {
      if (!mounted || _dialogShown || _dialogScheduled) return;
      _dialogScheduled = true;

      if (!mounted || _dialogShown) return;
      _dialogShown = true; // set before showing to avoid races
      MyGlobalMessage.show("Timeout", "No Reply From Base Station", MyMessageType.warning);
    });
  }

  // MQTT
  void _mqttStartListener() {
    if(_mqttSubscription != null) _mqttSubscription?.cancel();

    _mqttSubscription = MqttService().messageStream.listen((msg) async {
      if(!mounted) return;
      debugPrint('MQTT RX: $msg');

      final jsonData = jsonDecode(msg);
      final cmd = jsonData[mqttJsonCmd];
      //final fromId = jsonData[mqttJsonFromDeviceId];
      final payload = jsonData[mqttJsonPayload];

      // Tag Data (from any IOT)
      if (cmd == mqttCmdTagData) {
        if(tagRequested){
          tagRequested = false;

          _timeout?.cancel();

          // Pop Dialog box
          if (Navigator.canPop(navigatorKey.currentContext!)) {
            Navigator.pop(navigatorKey.currentContext!);
          }
          if(!mounted) return;
          final tagId = payload[mqttJsonTagData];
          _processTag(tagId);
        }
      }

      // ACK (from Base)
      if (cmd == mqttCmdAck) {
        _timeout?.cancel();
        debugPrint("ACK From Base");
      }

      // Connect Base (from Base)
      if (cmd == mqttCmdConnectBase) {
        _timeout?.cancel();
        context.read<SettingsService>().setIsBaseConnected(true);

        if(tagRequested){
          _requestTag();
        }

        var ip = context.read<SettingsService>().fireSettings!.connectedDeviceIp;
        var base = context.read<BaseStationService>().lstBaseStations.firstWhere((x) => x.ipAddress == ip);
        base.isConnected = true;

        final payload = jsonData[mqttJsonPayload];
        final savedCreds = await MqttCredentialsPreferences.saveFromPayload(
          payload: payload,
          baseId: base.bluetoothName,
        );
        if (savedCreds) {
          printDebugMsg('MQTT credentials saved for ${base.bluetoothName}');
        }

        MyGlobalSnackBar.show("Connected: $ip");
      }

    });
  }
  Future<bool> _mqttConnectBase () async {
    String? ip = context.read<SettingsService>().fireSettings?.connectedDeviceIp;
    String? deviceId = context.read<SettingsService>().fireSettings?.connectedDeviceId;

    if(ip == null || deviceId == null) {
      MyGlobalMessage.show(
          'Base Stations',
          'No previously connected base stations. Please set one in Base Stations page',
          MyMessageType.info
      );
      return false;
    }

    if(context.read<BaseStationService>().lstBaseStations.isEmpty){
      MyGlobalMessage.show(
          'Base Stations',
          'No Base Stations found. Please set one in Base Stations page',
          MyMessageType.info
      );
      return false;
    }

    BaseStationData base = context.read<BaseStationService>().lstBaseStations.firstWhere((x)  => x.bluetoothName == deviceId);

    await MqttCredentialsPreferences.syncFromFirestore(base.bluetoothName);

    String? wssHost;
    try {
      final cloud = await ClientCloudService.load(base.bluetoothName);
      final h = (cloud.mqttWssHost ?? '').trim();
      if (h.isNotEmpty) wssHost = MqttService.normalizeHost(h);
    } catch (_) {}

    bool isReady = await MqttService().restartService(
      ip,
      baseId: base.bluetoothName,
      wssHost: wssHost,
    );

    if(isReady) {
      _mqttStartListener();
      _startTimeout(5);

      MqttService().tx(
        base.bluetoothName,
        mqttCmdConnectBase,
        {fireUid: currentDataOwnerUid()},
        mqttTopicFromAndroid,
      );
      return true;
    }

    // Failed
    MyGlobalMessage.show("Warning", "Wifi connection FAILED", MyMessageType.warning);
    setState(() {
      base.isConnected = false;
    });

    return false;
  }

// Methods
  void _handleFocusChange(FocusNode node, String field) {
    if (!node.hasFocus) {
      final prevName = oldName;
      final prevSurname = oldSurname;
      setState(() {
        if (field == 'name')  widget.operatorData!.name = _controllerName!.text;
        if (field == 'surname')  widget.operatorData!.surname = _controllerSurname!.text;
        if (field == 'rate')  widget.operatorData!.rate = double.parse(_controllerRate!.text);
      });

      final nameChanged = field == 'name' || field == 'surname';
      if (nameChanged &&
          prevName == widget.operatorData!.name &&
          prevSurname == widget.operatorData!.surname) {
        return;
      }
      if (!nameChanged && field == 'rate') {
        context.read<OperatorService>().save(widget.operatorData!);
        return;
      }
      if (!nameChanged) return;

      unawaited(_saveNameAndAutoSync());
    }
  }

  Future<void> _saveNameAndAutoSync() async {
    await context.read<OperatorService>().save(widget.operatorData!);
    if (!mounted) return;
    oldName = widget.operatorData!.name;
    oldSurname = widget.operatorData!.surname;
    final ops = context.read<OperatorService>();
    IotBleOperatorSync.scheduleAutoSync(
      ops.lstOperators,
      operatorsVer: ops.lastOperatorsVer,
    );
  }
  Future<void> _requestTag() async{
    tagRequested = true;

    // Send Request
    // This only tells the Base to pass on any tags received from any IOTs
    MqttService().tx("",mqttCmdTagRequest,{}, mqttTopicFromAndroid );
    if(mounted) {
      MyGlobalMessage.show(
          "Read Tag",
          'Present a Tag On Any IOT Device That is in WiFi Range',
          MyMessageType.info
      );
    }
  }

  Future<BluetoothDevice?> _pickIotDevice(List<BluetoothDevice> devices) {
    return IotBleOperatorSync.showDevicePicker(context, devices);
  }

  Future<bool> _requestTagViaBluetooth() async {
    if (_bleReadBusy) return false;
    if (kIsWeb || !AppConfig.enableBluetooth) return false;

    setState(() => _bleReadBusy = true);
    IotBleOperatorSync.showBusyDialog(
      context,
      message: 'Scanning for wheels…',
    );

    try {
      final devices = await IotBleOperatorSync.scanForIotDevices();
      if (!mounted) return false;
      Navigator.of(context, rootNavigator: true).pop();

      if (devices.isEmpty) {
        return false; // caller may fall back to MQTT
      }

      final device = await _pickIotDevice(devices);
      if (device == null) return true; // user cancelled — don't MQTT

      if (!mounted) return true;
      IotBleOperatorSync.showBusyDialog(
        context,
        title: 'Bluetooth',
        message:
            'Present tag on ${IotBleOperatorSync.deviceLabel(device)}…',
      );

      final tagId = await IotBleOperatorSync.readTag(
        device: device,
        onStatus: printDebugMsg,
      );
      await IotBleOperatorSync.rememberDevice(device);

      if (!mounted) return true;
      Navigator.of(context, rootNavigator: true).pop();
      await _processTag(tagId);
      return true;
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      MyGlobalSnackBar.show('BLE tag read failed: $e');
      return true; // attempted BLE — don't also spam MQTT unless user retries
    } finally {
      if (mounted) setState(() => _bleReadBusy = false);
    }
  }

  Future<void> _onReadTagPressed() async {
    tagRequested = true;

    // Prefer direct BLE to the wheel (no base / WiFi needed)
    if (!kIsWeb && AppConfig.enableBluetooth) {
      final handled = await _requestTagViaBluetooth();
      if (handled) {
        tagRequested = false;
        return;
      }
      // No wheels nearby — fall back to MQTT if base is up
      if (!mounted) return;
      final baseUp =
          context.read<SettingsService>().isBaseStationConnected == true;
      if (baseUp) {
        await _requestTag();
        return;
      }
      MyGlobalSnackBar.show(
        'No IoT wheels found nearby. Turn on a wheel or connect a base station.',
      );
      tagRequested = false;
      return;
    }

    // Web / no BLE — MQTT via base
    if (context.read<SettingsService>().isBaseStationConnected) {
      await _requestTag();
    } else {
      await _mqttConnectBase();
    }
  }

  Future<void> _processTag(String tagId) async {
    // Check Tag duplication
    final uid = currentDataOwnerUid();

    final snapshot = await FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid!)
        .collection(collectionOperators)
        .where(operatorTagId, isEqualTo: tagId)
        .limit(1)
        .get();

    if(snapshot.docs.isNotEmpty){
      final existing = snapshot.docs.first;
      if (existing.id != widget.operatorData?.docId) {
        final Map<String, dynamic> data = existing.data();
        if (data[fireOperatorMarkedToDelete] == true) {
          // Tag was on a hidden operator — allow reuse.
        } else {
          String name = data[operatorName] ?? 'Unknown';
          String surname = data[operatorSurname] ?? 'Unknown';

          MyGlobalMessage.show("Duplicate Tag", "Tag in use by: $name $surname", MyMessageType.warning);
          return;
        }
      } else {
        // Same tag / Same Operator (Do nothing)
        return;
      }
    }

    if(widget.operatorData != null){
      setState(() {
        widget.operatorData!.tagId = tagId;
        _controllerTag!.text = tagId;
      });
    }

    MqttService().tx("", mqttCmdTagAck, {}, mqttTopicFromAndroid );

    // Save
    if(!mounted)return;
    context.read<OperatorService>().save(widget.operatorData!);
    debugPrint("Tag: $tagId");
  }
  void _deleteTagDialog(OperatorData operator) async {
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
            title: const MyText(
                text: "Delete",
                color: Colors.white
            ),
            content: MyText(
              text: "${operator.tagId} \nAre you sure?",
              color: Colors.grey,
              fontsize: 18,
            ),
            actions: [
              TextButton(
                child: const MyText(
                  text: 'No',
                  fontsize: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                  child: const MyText(
                    text: 'Yes',
                    color:  Colors.white,
                    fontsize: 20,
                  ),

                  onPressed: () async {
                    widget.operatorData!.tagId = "";
                    context.read<OperatorService>().save(widget.operatorData!);
                    _controllerTag!.text = "";

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
    if(_controllerName != null && _controllerSurname != null) {
      oldName = _controllerName!.text;
      oldSurname = _controllerSurname!.text;
    }
return Consumer<BaseStationService>(
    builder: (_,base,__){
      if (base.isLoading) {
        return myProgressCircle();
      }
      return Scaffold(
        backgroundColor: colorAppBackground,
        appBar: AppBar(
          backgroundColor: colorAppBar,
          foregroundColor: Colors.white,
          title: myAppbarTitle('Tag'),
        ),
        body: SafeArea(
          child: // Avatar
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [

                    // Profile Pic
                    GestureDetector(
                      onTap: () async {
                        final (ProfilePicData? profilePic) = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditProfilePicPage(
                              docId: widget.operatorData!.docId,
                              imageURL: widget.operatorData!.imageURL,
                              imageFilename: widget.operatorData!.imageFilename,
                              profileType: profileTypeOperator,
                            ),
                          ),
                        );
                        if(profilePic?.imageURL != null && profilePic!.update){
                          setState(() {
                            widget.operatorData!.imageURL = profilePic.imageURL;
                            widget.operatorData!.imageFilename = profilePic.imageFilename;
                          });
                          context.read<OperatorService>().save(widget.operatorData!);
                        }
                      },
                      child: CircleAvatar(
                        radius: 55,
                        backgroundColor: Colors.white,
                        child: kIsWeb
                            ? NetworkCircleAvatar(
                                imageUrl: widget.operatorData?.imageURL,
                                version: widget.operatorData?.imageFilename,
                                radius: 50,
                                backgroundColor: Colors.grey.shade300,
                              )
                            : CircleAvatar(
                                backgroundImage:
                                    widget.operatorData?.imageURL != null &&
                                            widget.operatorData!.imageURL!
                                                .isNotEmpty
                                        ? NetworkAvatar.imageProvider(
                                            widget.operatorData!.imageURL,
                                            version: widget
                                                .operatorData!.imageFilename,
                                          )
                                        : const AssetImage(iconProfile)
                                            as ImageProvider,
                                radius: 50,
                              ),
                      ),
                    ),

                    // Name Surname
                    SizedBox(height: 10),
                    MyText(

                      text: '${widget.operatorData!.name} ${widget.operatorData!.surname}',
                      fontsize: 20,
                    ),

                    // Line
                    Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Divider(thickness: 2,color: Colors.blueAccent)
                    ),

                    // Access Level
                    Padding(
                        padding:
                        const EdgeInsets.fromLTRB(10, 10, 10, 10),
                        child: MyDropdown(
                          label: 'Access Level',
                          value: normalizeAccessLevel(
                            widget.operatorData!.accessLevel,
                          ),
                          lstDropdownValues: settingOperatorTypeList,
                          onChange: (value) {
                            setState(() {
                              widget.operatorData!.accessLevel =
                                  normalizeAccessLevel(value);
                            });
                            context.read<OperatorService>().save(widget.operatorData!);
                          },
                        )
                    ),

                    // Name
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                      child: MyTextFormField(
                        focusNode: _focusNodeName,
                        backgroundColor: colorAppBackground,
                        foregroundColor: Colors.white,
                        controller: _controllerName,
                        labelText: "Name",
                        onFieldSubmitted: (value){
                          setState(() {
                            widget.operatorData!.name = value;
                          });
                          unawaited(_saveNameAndAutoSync());
                        },
                      ),
                    ),

                    // Surname
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                      child: MyTextFormField(
                        focusNode: _focusNodeSurname,
                        backgroundColor: colorAppBackground,
                        foregroundColor: Colors.white,
                        controller: _controllerSurname,
                        labelText: "Surname",
                        onFieldSubmitted: (value){
                          setState(() {
                            widget.operatorData!.surname = value;
                          });
                          unawaited(_saveNameAndAutoSync());
                        },
                      ),
                    ),

                    // Rate
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                      child: MyTextFormField(
                        focusNode: _focusNodeRate,
                        backgroundColor: colorAppBackground,
                        foregroundColor: Colors.white,
                        controller: _controllerRate,
                        labelText: "Rate",
                        inputType: TextInputType.numberWithOptions(decimal: true),
                        onFieldSubmitted: (value){
                          setState(() {
                            widget.operatorData!.rate = double.parse(value);
                          });
                          context.read<OperatorService>().save(widget.operatorData!);
                        },
                      ),
                    ),

                    // Tag ID  + Get Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                      child: Row(
                        children: [

                          // Tag ID
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0,10,15,10),
                              child: MyTextFormField(
                                isReadOnly: true,
                                backgroundColor: colorAppBackground,
                                foregroundColor: Colors.white,
                                controller: _controllerTag,
                                hintText: "none",
                                labelText: "Tag ID",
                                onFieldSubmitted: (value){},
                              ),
                            ),
                          ),

                          SizedBox(width: 15),

                          // Delete Button
                          InkWell(
                              onTap: () async {
                                _deleteTagDialog(widget.operatorData!);
                              },
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    size: 30,
                                    color: Colors.redAccent,
                                  ),
                                  SizedBox(width: 10),
                                   Text("Delete",
                                     style: TextStyle(
                                         color: Colors.white
                                   ),
                                  )
                                ],
                              )
                          ),

                          SizedBox(width: 15),

                          // Read Tag (BLE preferred, MQTT fallback)
                          InkWell(
                              onTap: _bleReadBusy
                                  ? null
                                  : () async {
                                      await _onReadTagPressed();
                                    },
                              child: Column(
                                children: [
                                  Icon(
                                    AppConfig.enableBluetooth
                                        ? Icons.bluetooth_searching
                                        : Icons.online_prediction_sharp,
                                    size: 30,
                                    color: _bleReadBusy
                                        ? Colors.grey
                                        : (AppConfig.enableBluetooth ||
                                                context
                                                    .read<SettingsService>()
                                                    .isBaseStationConnected)
                                            ? Colors.lightBlueAccent
                                            : Colors.grey,
                                  ),
                                  SizedBox(width: 10),
                                  Text("Read",
                                    style: TextStyle(
                                        color: Colors.white
                                    ),
                                  )
                                ],
                              )
                          ),
                        ],
                      ),
                    ),

                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
