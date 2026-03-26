import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
  int _selectedIndex = 0;
  TextEditingController? controllerName;
  TextEditingController? controllerSurname;
  TextEditingController? controllerTag;
  bool tagRequested = false;
  bool listenerStarted = false;
  late final SettingsService settingService;
  late final BaseStationService baseService;
  Timer? _timeout;
  bool _dialogScheduled = false; // prevents multiple registrations
  bool _dialogShown = false;     // prevents multiple dialogs


  @override
  void initState() {
    super.initState();

    controllerName = TextEditingController(text: widget.operatorData?.name ?? '');
    controllerSurname = TextEditingController(text: widget.operatorData?.surname ?? '');
    controllerTag = TextEditingController(text: widget.operatorData?.tagId ?? '');

    settingService = context.read<SettingsService>();
    baseService = context.read<BaseStationService>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      listenerStarted = false;
      mqtt_Service.isConnected = false;
      _setupMqttListener();
    });
  }

  @override
  void dispose() {
    mqtt_Service.stopMessageListener();
    mqtt_Service.isConnected = false;
    listenerStarted = false;
    tagRequested = false;
    _timeout?.cancel();
    controllerName?.dispose();
    controllerSurname?.dispose();
    controllerTag?.dispose();
    super.dispose();
  }

  // Timers
  void startTimer() {
    _timeout?.cancel();
    _dialogScheduled = false;
    _dialogShown = false;

    _timeout = Timer(const Duration(seconds: 5), () {
      if (!mounted || _dialogShown || _dialogScheduled) return;
      _dialogScheduled = true;

      if (!mounted || _dialogShown) return;
      _dialogShown = true; // set before showing to avoid races
      MyAlertDialog(context, "Comms Timeout", "No Reply From Base Station");
    });
  }

  // MQTT
  void _setupMqttListener() async {
    if( !listenerStarted){
      final ip = settingService.fireSettings?.connectedDeviceIp;
      if (ip == null || ip.isEmpty) return;

      if(!mqtt_Service.isConnected){
        final ok = await settingService.mqttConnect(ip);
        if (ok) {
          baseService.setConnectedByIp(ip, true);

          if (!listenerStarted) {
            listenerStarted = true;
            mqtt_Service.setupMessageListener();
            mqtt_Service.onMessage( MQTT_TOPIC_TO_ANDROID, _onMqttMessage);
            debugPrint("MQTT Listener Started");
          }
          else {
            debugPrint("MQTT listener - already Started");
          }
        }
        else{
          return;
        }
      }
    }
  }
  void _onMqttMessage(String msg) {
    debugPrint('MQTT RX: $msg');

    final Map<String, dynamic> jsonData = jsonDecode(msg);
    final cmd = jsonData[MQTT_JSON_CMD];

    // Tag Data (from any IOT)
    if (cmd == MQTT_CMD_TAG_DATA) {
      if(tagRequested){
        tagRequested = false;

        _timeout?.cancel();
        final payload = jsonData[MQTT_JSON_PAYLOAD];
        final tagId = payload[MQTT_JSON_TAG_DATA];

        // Pop Dialog box
        if (Navigator.canPop(navigatorKey.currentContext!)) {
          Navigator.pop(navigatorKey.currentContext!);
        }

        if(widget.operatorData != null){
          setState(() {
            widget.operatorData!.tagId = tagId.toString();
            controllerTag!.text = tagId.toString();
          });
        }

        mqtt_Service.tx("", MQTT_CMD_TAG_ACK, {}, MQTT_TOPIC_FROM_ANDROID );
        context.read<OperatorService>().save(widget.operatorData!);
        debugPrint("Tag: $tagId");
      }
    }

    // ACK (from Base)
    if (cmd == MQTT_CMD_ACK) {
      _timeout?.cancel();
      debugPrint("ACK From Base");
    }
  }

  Future<void> requestTag() async{
    final base = context.read<BaseStationService>();
    final settings = context.read<SettingsService>();

    if(base.lstBaseStations.isEmpty){
      MyAlertDialog(context,
          'Base Stations',
          'No Base Stations found. Please set one in Base Stations page'
      );
      return;
    }

    final ip = settings.fireSettings?.connectedDeviceIp;
    if (ip == null || ip.isEmpty) {
      MyAlertDialog(context,
          'Base Stations',
          'No Base Station connection found. Please connect to one in Base Stations page'
      );
      return;
    }

    if(!settings.isBaseStationConnected) {
      if(!await settings.mqttConnect(ip)){
        if(mounted){
          MyAlertDialog(context,
              'Base Stations',
              'Could not connect to Base Station. Please check that the Base Station is powered up and running'
          );
          return;
        }
      }
    }

    tagRequested = true;

    // Send Request
    // This only tells the Base to pass on any tags received from any IOTs
    mqtt_Service.tx("",MQTT_CMD_TAG_REQ,{}, MQTT_TOPIC_FROM_ANDROID );
    if(mounted) {
      MyAlertDialog(context,
          "Read Tag",
          'Present a Tag On Any IOT Device That is in WiFi Range');
    }

    startTimer();
  }
  Future<void> getImage() async{
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (widget.operatorData?.photoURL.isNotEmpty ?? false);

    return  Scaffold(
      backgroundColor: APP_BACKGROUND_COLOR,
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
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
                      final XFile? newImage = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditProfilePicPage(
                            image: widget.operatorData!.photoURL,
                          ),
                        ),
                      );
                      if(newImage != null){
                        widget.operatorData!.photoURL = newImage.path;
                      }
                    },
                    child: CircleAvatar(
                      radius: 55,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        backgroundImage: hasPhoto
                            ? NetworkImage(widget.operatorData!.photoURL) as ImageProvider
                            : AssetImage(IMAGE_PROFILE),
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
                      backgroundColor: APP_BACKGROUND_COLOR,
                      foregroundColor: Colors.white,
                      controller: controllerName,
                      hintText: "Enter Name",
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
                      backgroundColor: APP_BACKGROUND_COLOR,
                      foregroundColor: Colors.white,
                      controller: controllerSurname,
                      hintText: "Enter Surname",
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
                              backgroundColor: APP_BACKGROUND_COLOR,
                              foregroundColor: Colors.white,
                              controller: controllerTag,
                              hintText: "none",
                              labelText: "Tag ID",
                              onFieldSubmitted: (value){},
                            ),
                          ),
                        ),

                        SizedBox(width: 15),

                        // Connect Button
                        InkWell(
                            onTap: (){
                              requestTag();
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
  }
}
