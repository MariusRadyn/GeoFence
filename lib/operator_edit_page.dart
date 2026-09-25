import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
      setState(() {
        if (field == 'name')  widget.operatorData!.name = _controllerName!.text;
        if (field == 'surname')  widget.operatorData!.surname = _controllerSurname!.text;
        if (field == 'rate')  widget.operatorData!.rate = double.parse(_controllerRate!.text);

        if(oldName == widget.operatorData!.name && oldSurname == widget.operatorData!.surname) return;
        context.read<OperatorService>().save(widget.operatorData!);
      });
    }
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
                          context.read<OperatorService>().save(widget.operatorData!);
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
                          context.read<OperatorService>().save(widget.operatorData!);
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

                          // Connect Button
                          InkWell(
                              onTap: () async {
                                tagRequested = true;
                                context.read<SettingsService>().isBaseStationConnected
                                    ? _requestTag()
                                    : await _mqttConnectBase();
                              },
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.online_prediction_sharp,
                                    size: 30,
                                    color: context.read<SettingsService>().isBaseStationConnected
                                        ? Colors.blue
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
