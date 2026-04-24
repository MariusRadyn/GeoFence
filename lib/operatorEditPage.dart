import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/MqttService.dart';
import 'package:geofence/editProfilePicPage.dart';
import 'package:geofence/utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class OperatorEditPage extends StatefulWidget {
  final OperatorData? operatorData;

  const OperatorEditPage({
    required this.operatorData,
    super.key
  });

  @override
  State<OperatorEditPage> createState() => _OperatorEditPageState();
}
class _OperatorEditPageState extends State<OperatorEditPage> {
  TextEditingController? _controllerName;
  TextEditingController? _controllerSurname;
  TextEditingController? _controllerTag;
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

  @override
  void initState() {
    super.initState();

    _controllerName = TextEditingController(text: widget.operatorData?.name ?? '');
    _controllerSurname = TextEditingController(text: widget.operatorData?.surname ?? '');
    _controllerTag = TextEditingController(text: widget.operatorData?.tagId ?? '');

    _focusNodeName = FocusNode();
    _focusNodeSurname = FocusNode();

    _focusNodeName.addListener(() => _handleFocusChange(_focusNodeName, 'name'));
    _focusNodeSurname.addListener(() => _handleFocusChange(_focusNodeSurname, 'surname'));

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
    _mqttSubscription?.cancel();

    _mqttSubscription = MqttService().messageStream.listen((msg) {
      if(!mounted) return;
      debugPrint('MQTT RX: $msg');

      final jsonData = jsonDecode(msg);
      final cmd = jsonData[mqttJsonCmd];
      final fromId = jsonData[mqttJsonFromDeviceId];
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
      }

    });
  }


// Methods
  void _handleFocusChange(FocusNode node, String field) {
    if (!node.hasFocus) {
      setState(() {
        if (field == 'name')  widget.operatorData!.name = _controllerName!.text;
        if (field == 'surname')  widget.operatorData!.surname = _controllerSurname!.text;

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
    // CHeck Tag duplication
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final snapshot = await FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid!)
        .collection(collectionOperators)
        .where(operatorTagId, isEqualTo: tagId)
        .limit(1)
        .get();

    if(snapshot.docs.isNotEmpty){
      if (snapshot.docs.first.id != widget.operatorData?.docId) {
        final Map<String, dynamic> data = snapshot.docs.first.data();
        String name = data[operatorName] ?? 'Unknown';
        String surname = data[operatorSurname] ?? 'Unknown';

        MyGlobalMessage.show("Duplicate Tag", "Tag in use by: $name $surname", MyMessageType.warning);
        return;
      }
      // Same tag / Same Operator (Do nothing)
      return;
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
    bool isReady = await MqttService().restartService(ip);

        if(isReady) {
          _mqttStartListener();
          _startTimeout(5);

          MqttService().tx(base.bluetoothName, mqttCmdConnectBase, {} ,mqttTopicFromAndroid);
          return true;
        }

        // Failed
        MyGlobalMessage.show("Warning", "Wifi connection FAILED", MyMessageType.warning);
        setState(() {
          base.isConnected = false;
        });

        return false;
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
        return MyProgressCircle();
      }
      return Scaffold(
        backgroundColor: colorAppBackground,
        appBar: AppBar(
          backgroundColor: colorAppBar,
          foregroundColor: Colors.white,
          title: MyAppbarTitle('Operator'),
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
                        child: CircleAvatar(
                          backgroundImage:  widget.operatorData?.imageURL != null &&  widget.operatorData!.imageURL!.isNotEmpty
                              ? CachedNetworkImageProvider(widget.operatorData!.imageURL!) as ImageProvider
                              : AssetImage(imageProfile),
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
                          value: widget.operatorData!.accessLevel,
                          lstDropdownValues: settingOperatorTypeList,
                          onChange: (value) {
                            setState(() {
                              widget.operatorData!.accessLevel = value ?? '';
                            });
                            context.read<OperatorService>().save(widget.operatorData!);
                          },
                        )
                    ),

                    // Name
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
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
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
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

                    // Tag ID  + Get Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
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
