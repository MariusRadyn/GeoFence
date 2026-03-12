import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/firebase.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'MqttService.dart';

const APP_VERSION = "V1.0.1";

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool isDebug = true;
String debugLog = '';

const String  googleAPiKey = String.fromEnvironment('MAPS_API_KEY');
final mqtt_Service = MqttService();

// keytool -keystore C:\Users\mradyn\.android\debug.keystore -list
// PW android

//---------------------------------------------------
// Constants Images
//---------------------------------------------------
const String IMAGE_WHEEL = "assets/distanceWheel.jpg";
const String IMAGE_VEHICLE = "assets/red_pickup2.png";
const String IMAGE_MOBILE_MACHINE = "'assets/tractor.jpg'";
const String IMAGE_STATIONARY_MACHINE = "assets/generator.jpg";
const String IMAGE_NO_IMAGE = 'assets/noImage.jpg';
const String IMAGE_PROFILE = 'assets/profile.png';

const String ICON_WARNING = "assets/warning.png";
const String ICON_GOOGLE = 'assets/google_icon.png';
const String ICON_FACEBOOK = 'assets/facebook_icon.png';
const String ICON_TRACK = 'assets/track.jpg';
const String ICON_GEOFENCE = 'assets/geofence.jpg';
const String ICON_IOT = 'assets/iot.png';
const String ICON_BASE = 'assets/base_station.png';
const String ICON_REPORT = 'assets/report.png';
const String ICON_LIMITLESS_LOGO = 'assets/limitless_logo.png';
const String ICON_LIMITLESS_WORD = 'assets/limitlessIotWord.png';

//---------------------------------------------------
// Constants Colors
//---------------------------------------------------
const COLOR_ICE_BLUE = Color.fromARGB(202, 139, 229, 245);
const COLOR_BLUE = Color.fromARGB(255, 4, 145, 246);
const COLOR_DARK_BLUE = Color.fromARGB(255, 1, 57, 86);
const COLOR_DARK_HEADER = Colors.white;
const COLOR_DARK_TEXT = Colors.white;
const COLOR_BLACK = Color(0xFF14140F);
const COLOR_BLACK_LIGHT = Color(0x10A3CCAB);
const COLOR_TEAL_LIGHT = Color(0xFFA3CCAB);
const COLOR_TEAL_MID = Color(0xFF34675C);
const COLOR_TEAL_DARK = Color(0xFF053D38);
const COLOR_ORANGE = Color.fromARGB(255, 255, 60, 1);
const COLOR_GREY = Color.fromARGB(139, 119, 119, 119);
const COLOR_LIGHT_GREY = Color.fromARGB(137, 222, 222, 222);

const APP_BAR_COLOR = Color.fromARGB(255, 0, 36, 52);
const APP_BACKGROUND_COLOR = COLOR_DARK_BLUE;
const APP_TILE_COLOR = Color.fromARGB(255, 21, 34, 52);
const DRAWER_COLOR = Color.fromARGB(255, 33, 137, 215);
const PROGRESS_CIRCLE_COLOR = Colors.lightBlueAccent ;

final FirebaseAuthService firebaseAuthService = FirebaseAuthService();
final FirebaseFirestore firestore = FirebaseFirestore.instance;

final String fireUserName = 'user1';
final String fireUserRecyclebin = '${fireUserName}_recycle/';
const String DB_TABLE_USERS = 'UserTable';



//---------------------------------------------------
// Firebase Settings
//---------------------------------------------------
const CollectionUsers = 'users';
const CollectionGeoFences = 'geofences';
const CollectionTrackingSessions = 'tracking_sessions';
const CollectionLocations = 'locations';
const CollectionMonitors = 'monitors';
const CollectionMonitorData = 'iotdata';
const CollectionServers = 'servers';
const CollectionClients = 'clients';

const FieldsSettings = 'settings';
const FieldsUserData = 'userdata';

const DocAppSettings = 'app_settings';

// General Settings
const SettingIsVoicePromptOn = 'isVoicePromptOn';
const SettingLogPointPerMeter = 'logPointPerMeter';
const SettingRebateValue = 'rebateValuePerLiter';
const SettingDieselPrice = 'dieselPrice';
const SettingConnectedDevice = 'connectedDevice';
const SettingConnectedDeviceIp = 'connectedDeviceIp';
const SettingServerData = 'serverData';
const double SettingMonDefaultTicksPerM = 20; // Default value when new Monitor is created

// Monitor Types
const List<String> SettingMonitorTypeList = [
  MonTypeVehicle,
  MonTypeMobileMachineMon,
  MonTypeStationaryMachineMon,
  MonTypeWheel,
];

// Monitor Types
const String MonTypeVehicle = "Vehicle";
const String MonTypeMobileMachineMon = "Mobile Machine";
const String MonTypeStationaryMachineMon = "Stationary Machine";
const String MonTypeWheel = "Distance Wheel";

// Monitor Log Data
const LogMonDocId = 'monDocId';
const LogMonUserDocId = 'userDocId';
const LogMonType = 'iotType';
const LogMonName = 'name';
const LogMonDistance = 'distance';
const LogMonLines = 'lines';
const LogMonOperator = 'operator';
const LogMonSupervisor = 'supervisor';
const LogMonTimestamp = 'timestamp';

// Monitor Debug
const DebugMonitorConnected = 'debugConnected';
const DebugMonitorWheelDistance = 'debugWheelDistance';
const DebugMonitorWheelSignal = 'debugWheelSignal';

// Firebase - Base Station Settings
const FIRE_BASE_NAME = 'name';
const FIRE_BASE_DESC = 'description';
const FIRE_BASE_IP = 'ipAdr';
const FIRE_BASE_BT_NAME = 'bluetoothDeviceName';
const FIRE_BASE_BT_MAC = 'bluetoothMAC';
const FIRE_BASE_IMAGE = 'image';

// Firebase - Monitor settings
const FIRE_MON_NAME = 'name';
const FIRE_MON_FUEL_CONSUMPTION = 'fuelConsumption';
const FIRE_MON_REGISTRATION = 'registrationNumber';
const FIRE_MON_BT_NAME = 'bluetoothDeviceName';
const FIRE_MON_BT_MAC = 'bluetoothMAC';
const FIRE_MON_IMAGE = 'picture';
const FIRE_MON_TYPE = 'type';
const FIRE_MON_ID = 'monitorId';
//const FIRE_MON_DOC_ID = 'monDocId';
//const FIRE_MON_USER_DOC_ID = 'userDocId';
const FIRE_MON_TICKS_PER_M = 'ticksPerM';
const FIRE_MON_TIMESTAMP = 'timestamp';
const FIRE_MON_LAST_LOG_TIMESTAMP = 'lastLogTimestamp';

// Firebase - Tracking settings
const FIRE_TRACK_DIST_IN = 'distance_inside';
const FIRE_TRACK_DIST_OUT = 'distance_outside';
const FIRE_TRACK_START_TIME = 'start_time';
const FIRE_TRACK_END_TIME = 'end_time';
const FIRE_TRACK_ACTIVE = 'is_active';
const FIRE_TRACK_VEH_DOC_ID = 'vehicle_id';


// Clients Settings
const SettingClientIpAdr = 'IPAdress';

// MQTT Topics
const MQTT_TOPIC_FROM_IOT = "mqtt/from/iot";
const MQTT_TOPIC_TO_IOT = "mqtt/to/iot";
const MQTT_TOPIC_TO_ANDROID = "mqtt/to/android";
const MQTT_TOPIC_FROM_ANDROID = "mqtt/from/android";
const MQTT_TOPIC_WILL = "mqtt/will";

// MQTT Commands
const MQTT_CMD_REQ_MONITOR = "#REQ_MONITOR";
const MQTT_CMD_FOUND_MONITOR = "#FOUND_MONITOR";
const MQTT_CMD_CONNECT_MONITOR = "#CONNECT_MONITOR";
const MQTT_CMD_DISCONNECT_MONITOR = "#DISCONNECT_MONITOR";
const MQTT_CMD_ACK = "#ACK";
const MQTT_CMD_MONITOR_DATA = "#MONITOR_DATA";

// MQTT Payload
const MQTT_JSON_FROM_DEVICE_ID = "from";
const MQTT_JSON_TO_DEVICE_ID = "to";
const MQTT_JSON_TOPIC = "topic";
const MQTT_JSON_PAYLOAD = "payload";
const MQTT_JSON_CMD = "cmd";
const MQTT_JSON_WHEEL_DISTANCE = "wheel_distance";

// JSON Settings
const MQTT_JSON_MON_ID = "monId";
const MQTT_JSON_TICKS_PER_M = "ticksPerM";
const MQTT_JSON_IOT_TYPE = "iotType";
const MQTT_JSON_IOT_NAME = "iotName";
const MQTT_JSON_MON_DOC_ID = "monDocId";
const MQTT_JSON_USER_DOC_ID = "userDocId";


//---------------------------------------------------
// Bluetooth
//---------------------------------------------------
const BT_SERVICE_UUID = 'f3a1c2d0-6b4e-4e9a-9f3e-8d2f1c9b7a1e';
const BT_CHAR_UUID = 'c7b2e3f4-1a5d-4c3b-8e2f-9a6b1d8c2f3a';

//---------------------------------------------------
// Methods
//---------------------------------------------------
void printMsg(String msg) {
  if (isDebug) print(msg);
}
void writeLog(var text) {
  debugLog += text +'\r';
}
bool isOnDesktop() {
  if(kIsWeb) {
    return true;
  } else {
    return false;
  }
}
bool isPointInsidePolygon(LatLng point, List<LatLng> polygon) {
  bool isInside = false;
  int j = polygon.length - 1;

  for (int i = 0; i < polygon.length; i++) {
    final xi = polygon[i].longitude;
    final yi = polygon[i].latitude;
    final xj = polygon[j].longitude;
    final yj = polygon[j].latitude;

    final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi + 0.0000001) + xi);

    if (intersects) {
      isInside = !isInside;
    }

    j = i;
  }

  return isInside;
}
LatLng calculateCentroid(List<LatLng> points) {
  double latitude = 0;
  double longitude = 0;

  for (var point in points) {
    latitude += point.latitude;
    longitude += point.longitude;
  }

  return LatLng(latitude / points.length, longitude / points.length);
}
Position latLngToPosition(LatLng latLng) {
  return Position(
    latitude: latLng.latitude,
    longitude: latLng.longitude,
    timestamp: DateTime.now(),
    headingAccuracy: 0.0,
    altitudeAccuracy: 0.0,
    accuracy: 0.0,
    altitude: 0.0,
    heading: 0.0,
    speed: 0.0,
    speedAccuracy: 0.0,
    floor: null,
    isMocked: false,
  );
}
void myMessageBox (BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false, // Prevents accidental closing
    builder: (context) => _myMessageBox(message: message ),
  );
}
class _myMessageBox extends StatelessWidget {
  final String message;
  final String header;
  final String image;
  final Color borderColor;

  _myMessageBox({
    required this.message,
    this.header = '',
    this.image = ICON_WARNING,
    this.borderColor = Colors.blueAccent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 20,
      shadowColor: Colors.black87,
      backgroundColor: APP_TILE_COLOR,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: borderColor, // Border color
          width: 2, // Border width
        ),
      ),
      child: SizedBox(
        width: 250,
        height: 220, // Increased height for close button
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close Button (Top-Right)
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(
                    Icons.close,
                    color: Colors.grey
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // Heading with Image
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(image, height: 30, width: 30),
                SizedBox(width: 8),
                MyText(
                  text:  header,
                  fontsize: 18,
                  color: Colors.white,
                ),
              ],
            ),
            SizedBox(height: 10),

            // Message
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: MyText(
                text:  message,
                color: Colors.grey,
                fontsize: 14,
              ),
            ),
            SizedBox(height: 20),

            // OK Button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
              },
              child: const MyText(
                text: "OK",
                fontsize: 20,
                color: Colors.blueAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class MyDialogWidget extends StatelessWidget {
  final String message;
  final String header;
  final String but1Text;
  final String but2Text;
  final VoidCallback? onPressedBut1;
  final VoidCallback? onPressedBut2;
  final String image;

  const MyDialogWidget({
    super.key,
    required this.message,
    required this.header,
    required this.but1Text,
    required this.but2Text,
    this.onPressedBut1,
    this.onPressedBut2,
    this.image = ICON_WARNING,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Row(
        children: [
          Expanded(flex: 1, child: Image.asset(image, height: 30, width: 30)),
          SizedBox(width: 20),

          // Header
          Expanded(flex: 4, child: MyText(
            text: header,
            fontsize: 18,
            color: Colors.white
            ),
          ),
        ],
      ),

      // Message
      content: MyText(
        text: message,
        fontsize: 14,
        color: Colors.grey,
      ),
      actions: <Widget>[
        TextButton(
          style: TextButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          onPressed: onPressedBut1,
          child: MyText(
            text: but1Text,
            fontsize: 20,
            color: Colors.blueAccent,
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          onPressed: onPressedBut2,
          child: MyText(
            text: but2Text,
            fontsize: 20,
            color: Colors.blueAccent,
          ),
        ),
      ],
    );
  }
}
class Grabber extends StatelessWidget {
  /// A draggable widget that accepts vertical drag gestures
  /// and this is only visible on desktop and web platforms.
  const Grabber({super.key, required this.onVerticalDragUpdate, required this.isOnDesktopAndWeb});

  final ValueChanged<DragUpdateDetails> onVerticalDragUpdate;
  final bool isOnDesktopAndWeb;

  @override
  Widget build(BuildContext context) {
    if (!isOnDesktopAndWeb) {
      return const SizedBox.shrink();
    }
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onVerticalDragUpdate: onVerticalDragUpdate,
      child: Container(
        width: double.infinity,
        color: colorScheme.onSurface,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            width: 32.0,
            height: 4.0,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ),
      ),
    );
  }
}

//---------------------------------------------------
// Dialog
//---------------------------------------------------
void MyAlertDialog(BuildContext context, String header, String message){
  // Show popup with file path
  showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(
            color: Colors.blue, // Border color
            width: 2, // Border width
          ),
        ),
        backgroundColor: APP_TILE_COLOR,
        shadowColor: Colors.black,

        // Header
        title: Text(header,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
          ),
        ),

        // Message
        content: Text(message,
          style: TextStyle(
              color: Colors.grey,
            fontSize: 14
          ),
        ),
        actions: [
         TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const MyText(
              text: 'OK',
              color: Colors.blueAccent,
              fontsize: 20
            ),
         ),
        ],
      ),
  );
}

//---------------------------------------------------
// Class
//---------------------------------------------------
class Point {
  final double x, y;
  Point(this.x, this.y);
}
class FenceData{
  String polygonId;
  String firestoreId;
  String name;
  List<LatLng> points;

  FenceData({
    this.points = const [],
    this.name = "",
    this.firestoreId = "",
    this.polygonId = "",
  });
}
class BluetoothData{
  String name;
  String id;

  BluetoothData({
    this.name = "",
    this.id = "",
  });
}
class MyTextFormField extends StatefulWidget {
  final TextEditingController? controller;
  final bool isPasswordField;
  final bool isReadOnly;
  final String? hintText;
  final String? labelText;
  final String? helperText;
  final String suffix;
  final FormFieldSetter<String>? onSaved;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? inputType;
  final double? width;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const MyTextFormField({
    super.key,
    this.controller,
    this.isPasswordField = false,
    this.hintText,
    this.labelText,
    this.helperText,
    this.suffix = '',
    this.onSaved,
    this.validator,
    this.width,
    this.onFieldSubmitted,
    this.onChanged,
    this.inputType,
    this.backgroundColor = Colors.white,
    this.foregroundColor = Colors.black,
    this.isReadOnly = false,
  });

  @override
  _MyTextFormFieldState createState() => _MyTextFormFieldState();
}
class _MyTextFormFieldState extends State<MyTextFormField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    List<TextInputFormatter>? inputFormatters;
    if (widget.inputType == TextInputType.number ||
        widget.inputType == const TextInputType.numberWithOptions(decimal: false)) {
      inputFormatters = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,}$'))];
    } else if (widget.inputType ==
        const TextInputType.numberWithOptions(decimal: true)) {
      inputFormatters = [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ];
    } else {
      inputFormatters = null; // No restriction
    }

    return Container(
      width: widget.width,
      height: 55,
      child: TextFormField(
        style: TextStyle(
          fontSize: 15,
          color: widget.foregroundColor,
          fontFamily: 'Poppins',
        ),

        readOnly: widget.isReadOnly,
        controller: widget.controller,
        keyboardType: widget.inputType,
        inputFormatters: inputFormatters,
        key: widget.key,
        obscureText: widget.isPasswordField == true ? _obscureText : false,
        onSaved: widget.onSaved,
        onChanged: widget.onChanged,
        validator: widget.validator,
        onFieldSubmitted: widget.onFieldSubmitted,
        decoration: InputDecoration(
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
            color: Colors.grey
            ),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
            color: Colors.blue,
            ),
          ),

          filled: true,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          fillColor: widget.backgroundColor,
          suffix: Text(widget.suffix),
          hintText: widget.hintText,
          hintStyle: TextStyle(
            color: Colors.grey,
            fontSize: 16,
            fontFamily: 'Poppins',
          ),

          labelText: widget.labelText,
          labelStyle: TextStyle(
            color: Colors.grey,
            fontSize: 20,
            fontFamily: 'Poppins',
          ),

          suffixIcon: GestureDetector(
            onTap: () {
              setState(() {
                _obscureText = !_obscureText;
              });
            },
            child:
              widget.isPasswordField == true
                ? Icon( _obscureText
                    ? Icons.visibility_off
                    : Icons.visibility,

                  color: _obscureText == false
                   ? Colors.blue
                   : Colors.grey,
                )
                : Text(""),
          ),
        ),
      ),
    );
  }
}
class MyCustomTileWithPic extends StatelessWidget {
  final String imagePath;
  final String header;
  final String description;
  final Widget widget;

  const MyCustomTileWithPic({
    required this.imagePath,
    required this.header,
    this.description = "",
    required this.widget,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    UserDataService user = context.read<UserDataService>();

    return Padding(
      padding: const EdgeInsets.only(top: 5, bottom: 5),
      child: Center(
        child: GestureDetector(
          onTap: (){
            if(user.isLoggedIn == true){
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => widget),
              );
            }else{
              myMessageBox(context, "User not Logged In");
            }
          },
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [
                  0.1,
                  0.9
                ],
                colors: [
                  COLOR_BLUE,
                  Colors.black,
                ],
              ),
              borderRadius:const BorderRadius.all(
                Radius.circular(20),
              ),
              border: Border.all(
                color: Colors.grey,
                width: 2,
              )
            ),
            child:
              Row(
                children: [
                  // Image
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                    child: Image.asset (
                        imagePath,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Heading Text
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        //const SizedBox(height: 5),

                        Text(
                          header,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.normal,
                              fontFamily: 'Poppins'
                          ),
                          softWrap: true,
                        ),

                        Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Text(
                            description,
                            style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontWeight: FontWeight.normal,
                                fontFamily: 'Poppins'
                            ),
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 3,
                            textAlign: TextAlign.start,
                          ),

                        ),

                        const SizedBox(height: 5),
                      ],
                    ),
                  ),
                ],
              ),
          ),
        ),
      ),
    );
  }
}
class MyIcon extends StatelessWidget {
  final String text;
  final IconData icon;
  final GestureTapCallback onTap;
  final Color iconColor;
  final Color textColor;
  final double iconSize;
  final double textSize;

  const MyIcon({
    required this.text,
    required this.icon,
    this.onTap = _defaultOnTap,
    this.iconColor = Colors.black,
    this.textColor = Colors.black,
    this.iconSize = 30,
    this.textSize = 12,
    super.key
  });

  static void _defaultOnTap(){}

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: EdgeInsets.all(5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: iconSize,
                color: iconColor,
              ),

              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: textSize,
                    fontWeight: FontWeight.normal,
                    color: textColor,
                ),
              ),
            ],
          ),
        ),
      );
  }
}
class MyTextOption extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String description;
  final String measure;
  final String prefix;
  final String suffix;

  const MyTextOption({super.key,
    required this.controller,
    required this.label,
    this.description = "",
    this.measure = "",
    this.prefix = "",
    this.suffix = ""
  });

  @override
  Widget build(BuildContext context) {
    return  Padding(
      padding: const EdgeInsets.only(left: 10.0, right: 10, bottom: 5),
      child: Container(
        padding: EdgeInsets.only(top: 10, bottom: 10,left: 15),
        // decoration: BoxDecoration(
        //   gradient: MyTileGradient(),
        //   border: Border.all(
        //     color: Colors.grey,
        //     width: 1
        //   ),
        //   borderRadius: BorderRadius.circular(8),
        // ),
        child: Row(
          //mainAxisAlignment: MainAxisAlignment.start,
          //crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Label and Description
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.normal,
                      fontSize: 18,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    description,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 2),

            Expanded(
              flex: 1,
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '0',
                  border: OutlineInputBorder(),
                  suffixText: suffix,
                  prefixText: prefix,
                  prefixStyle: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                  ),
                    suffixStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  )
                ),

                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.normal,
                  fontSize: 20,
                ),
              ),
            ),
            SizedBox(width: 5),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
class MyToggleOption extends StatelessWidget {
  final bool value;
  final String label;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  const MyToggleOption({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle = "",
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10.0, right: 10,bottom: 5),
      child: Container(
        padding: EdgeInsets.only(top: 8, bottom: 8),
        // decoration: BoxDecoration(
        //   gradient: MyTileGradient(),
        //   border: Border.all(
        //       color: Colors.grey,
        //       width: 1
        //   ),
        //   borderRadius: BorderRadius.circular(8),
        // ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.normal,
                  fontSize: 18,
                ),
              ),
              subtitle: Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.grey,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.normal,
                  fontSize: 14,
                ),
              ),
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
class MyText extends StatelessWidget {
  final String text;
  final double? fontsize;
  final Color color;

  const MyText({
    required this.text,
    this.fontsize = 16,
    this.color = Colors.white,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      softWrap: true,
      style: TextStyle(
        color: color,
        fontFamily: 'Poppins',
        fontWeight: FontWeight.normal,
        fontSize: fontsize,
      ),
    );
  }
}
class MyTextHeader extends StatelessWidget {
  final String text;
  final double? fontsize;
  final Color color;
  final Color linecolor;

  const MyTextHeader({
    required this.text,
    this.fontsize = 16,
    this.color = Colors.white,
    this.linecolor = Colors.blue,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return  Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text,
          style: TextStyle(
            fontSize: fontsize,
            fontFamily: 'Poppins',
            color: color,
          ),
          softWrap: true,
        ),
        Divider(
          thickness: 2,
          color: linecolor,
        )
      ],
    );
  }
}
class MyTextTileWithEditDelete extends StatelessWidget {
  final String header;
  final String subtext;
  final VoidCallback? onTapEdit;
  final VoidCallback? onTapDelete;
  final VoidCallback? onTapTile;
  final VoidCallback? onTapReport;
  final LinearGradient? gradient;
  final Color? backgroundColor;
  final Color headerColor;
  final Color textColor;
  final String? image;
  final double? height;

  MyTextTileWithEditDelete({
    required this.header,
    required this.subtext,
    this.onTapEdit,
    this.onTapDelete,
    this.onTapTile,
    this.onTapReport,
    LinearGradient? gradient ,
    this.backgroundColor,
    this.headerColor = Colors.white,
    this.textColor = Colors.white,
    this.image,
    this.height,
    super.key
  }) : gradient = gradient ?? MyTileGradient();

  @override
  Widget build(BuildContext context) {

    double imgHeight = height == null ? 30 : height! - 30;

    return GestureDetector(
      onTap: () {
        if(onTapTile != null) {
          onTapTile!();
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20,0,20,0),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(30),
            gradient: gradient,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30,0,10,0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [

                // Text
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Header
                      MyText(
                        text: header,
                        color: headerColor,
                        fontsize: 18,
                      ),

                      SizedBox(height: 1),

                      // Text
                      MyText(
                        text: subtext,
                        color: textColor,
                        fontsize: 14,
                      ),
                    ],
                  ),
                ),

                // Image
                image == null
                    ? SizedBox()
                    : Row(
                  children: [
                    Container(
                      height: imgHeight,
                      width: imgHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.elliptical(30, 30)),
                        image: DecorationImage(
                          image: AssetImage(image!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 10),

                // Icons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if(onTapEdit != null)
                      IconButton(
                        icon: Icon(Icons.edit, color: Colors.white,),
                        onPressed: () => onTapEdit!(),
                        iconSize: 35,
                        constraints: BoxConstraints(),
                      ),

                    if(onTapDelete != null)
                      IconButton(
                        icon: Icon(Icons.delete_forever, color: Colors.pinkAccent),
                        onPressed: () => onTapDelete!(),
                        iconSize: 35,
                        constraints: BoxConstraints(),
                      ),

                    if(onTapReport != null)
                      IconButton(
                        icon: Icon(Icons.list_alt, color: Colors.blue,),
                        onPressed: () => onTapReport!(),
                        iconSize: 35,
                        constraints: BoxConstraints(),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class MyCircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const MyCircleIconButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
class MyVehicleData extends StatefulWidget {
  final DocumentSnapshot? vehicleSnapshot;
  final String bluetoothDeviceName;
  final String bluetoothMAC;
  final List<BluetoothDevice> pairedDevices;

  MyVehicleData({
    super.key,
    required this.vehicleSnapshot,
    this.bluetoothMAC = "",
    this.bluetoothDeviceName = "",
    List<BluetoothDevice>? pairedDevices
  }) : pairedDevices = pairedDevices ?? [];

  @override
  State<MyVehicleData> createState() => _MyVehiclesDataState();
}
class _MyVehiclesDataState extends State<MyVehicleData> {
  TextEditingController vehicleNameController = TextEditingController();
  TextEditingController fuelConsumptionController = TextEditingController();
  TextEditingController vehicleRegController = TextEditingController();
  BluetoothDevice? selectedDevice;

  late String bluetoothDeviceName;
  late String bluetoothMAC;
  late List<BluetoothDevice> pairedDevices;

  @override
  void initState() {
    super.initState();
    bluetoothDeviceName = widget.bluetoothDeviceName;
    bluetoothMAC = widget.bluetoothMAC;
    pairedDevices = List.from(widget.pairedDevices);
    loadSettings();
  }

  void loadSettings() {
    vehicleNameController = TextEditingController(
        text: widget.vehicleSnapshot != null ? widget.vehicleSnapshot![FIRE_MON_NAME] : ''
    );
    fuelConsumptionController = TextEditingController(
        text: widget.vehicleSnapshot != null ? widget.vehicleSnapshot![FIRE_MON_FUEL_CONSUMPTION].toString() : ''
    );
    vehicleRegController = TextEditingController(
        text: widget.vehicleSnapshot != null ? widget.vehicleSnapshot![FIRE_MON_REGISTRATION] : ''
    );

    if (widget.vehicleSnapshot != null) {
      bluetoothDeviceName = widget.vehicleSnapshot![FIRE_MON_BT_NAME];
      bluetoothMAC = widget.vehicleSnapshot![FIRE_MON_BT_MAC];
    }
  }

  @override
  void dispose() {
    vehicleNameController.dispose();
    fuelConsumptionController.dispose();
    vehicleRegController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    loadSettings();

    return Container(
      color: APP_BACKGROUND_COLOR,
      child:  Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Vehicle Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8,vertical: 5,),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Header
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                  child: MyTextHeader(
                    text: 'Vehicle Information',
                    color: Colors.white,
                    fontsize: 16,
                  ),
                ),

                // Vehicle Name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
                  child: MyTextFormField(
                    backgroundColor: APP_BACKGROUND_COLOR,
                    foregroundColor: Colors.white,
                    controller: vehicleNameController,
                    hintText: "Enter value here",
                    labelText: "Vehicle Name",
                    onFieldSubmitted: (value){
                    },
                  ),
                ),

                // FuelConsumption
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
                  child: MyTextFormField(
                    backgroundColor: APP_BACKGROUND_COLOR,
                    foregroundColor: Colors.white,
                    controller: fuelConsumptionController,
                    hintText: "Enter value here",
                    labelText: "Consumption",
                    suffix: "l/100Km",
                    inputType: TextInputType.number,
                    onFieldSubmitted: (value){
                    },
                  ),
                ),

                // Reg Number
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
                  child: MyTextFormField(
                    backgroundColor: APP_BACKGROUND_COLOR,
                    foregroundColor: Colors.white,
                    controller: vehicleRegController,
                    hintText: "Enter value here",
                    labelText: "Registration Number",
                    onFieldSubmitted: (value){
                    },
                  ),
                ),
                SizedBox(height: 10),
              ],
            ),
          ),

          // Bluetooth
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Header
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 15,horizontal: 5),
                  child: MyTextHeader(
                    text:'Bluetooth',
                    color: Colors.white,
                    fontsize: 16,
                    ),
                  ),

                // Help text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Text('Use bluetooth connection in the vehicle to get vehicle ID. '
                      'Select which bluetooth connection to use in the vehicle. '
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

                SizedBox(height: 10),

                // Select Bluetooth
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 20),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      // Set items list background color
                        canvasColor: APP_TILE_COLOR
                    ),
                    child: DropdownButtonFormField<BluetoothDevice>(
                      value: selectedDevice,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Select Bluetooth Device',
                        labelStyle: TextStyle(color: Colors.grey),
                        fillColor: APP_BACKGROUND_COLOR,
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      hint: Text(pairedDevices.isEmpty ? 'No paired devices' : 'Choose a paired device',
                        style: TextStyle(color: Colors.grey),
                      ),

                      items: pairedDevices.map((BluetoothDevice device) {
                        return DropdownMenuItem<BluetoothDevice>(
                          value: device,
                          child: Row(
                            children: [
                              Icon(
                                Icons.bluetooth,
                                size: 20,
                                color: device.isConnected ? Colors.green : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      device.platformName.isNotEmpty
                                          ? device.platformName
                                          : 'Unknown Device',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      device.remoteId.toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (BluetoothDevice? device) {
                        setState(() {
                          if(device != null){
                            selectedDevice = device;
                            bluetoothMAC = device.remoteId.toString();
                            bluetoothDeviceName = device.platformName;
                          }
                        });
                        //if (onDeviceSelected != null) {
                        //  onDeviceSelected!(device);
                        //}
                      },
                      isExpanded: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class GlobalMsg {
  static void show(String header, String message) {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(
            color: Colors.blue, // Border color
            width: 2, // Border width
          ),
        ),
        backgroundColor: APP_TILE_COLOR,
        shadowColor: Colors.black,
        title: MyText(
            text: header,
            color: Colors.white
        ),
        content: MyText(
          text: message,
          color: Colors.grey,
          fontsize: 18,
        ),
        actions: [
          TextButton(
              child: const MyText(
                text: 'OK',
                color:  Colors.white,
                fontsize: 20,
              ),

              onPressed: () async {
                Navigator.pop(context);
              }
          ),
        ],
      ),
    );
  }
}
class MyGlobalSnackBar {
  static void show(String message) {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: MyText(
            text: message
        ),
        backgroundColor: Colors.blueGrey,
      ),
    );
  }
}
Future<T?> MyQuestionAlertBox<T> ({
  required BuildContext context,
  required String header,
  required String message,
  VoidCallback? onPress,
}) {
    return showDialog(
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
            backgroundColor: APP_TILE_COLOR,
            shadowColor: Colors.black,
            title: MyText(
                text: header,
                color: Colors.white,
              fontsize: 18,
            ),
            content: MyText(
              text: message,
              color: Colors.grey,
              fontsize: 16,
            ),
            actions: [
              TextButton(
                child: const MyText(
                  text: 'No',
                  fontsize: 20,
                  color: Colors.blue,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                  child: const MyText(
                    text: 'Yes',
                    color:  Colors.blue,
                    fontsize: 20,
                  ),

                  onPressed: () {
                    if(onPress != null){
                      onPress();
                    }
                    Navigator.pop(context);
                  }
              ),
            ],
          );
        }
    );
}
class ClientIdManager {
  static const _key = "mqtt_client_id";

  static Future<String> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_key);

    if (id == null) {
      // Generate a short unique ID (MQTT-safe)
      id = "android_${const Uuid().v4().substring(0, 8)}";
      await prefs.setString(_key, id);
      MyGlobalSnackBar.show("MQTT DeviceID Generated: $id");
    }

    return id;
  }
}
class MyDropdown extends StatelessWidget {
  final ValueChanged<String?>? onChange;
  final String value;

  const MyDropdown({
    super.key,
    required this.onChange,
    required this.value
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      dropdownColor: APP_BAR_COLOR,
      decoration: InputDecoration(
        labelText: "Monitor Type",
        labelStyle: TextStyle(color: Colors.grey, fontSize: 22),
        enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue)
        ),

        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.blue, width: 2),
        ),
      ),
      //value: SettingMonitorTypeList.contains(monitor[SettingMonitorType]) ? monitor[SettingMonitorType] : null,
      value: value,
      hint: const Text("Select Monitor Type",
        style: TextStyle(
          color: Colors.grey,
          fontFamily: 'Poppins',
          fontSize: 15,
        ),
      ),
      items: SettingMonitorTypeList.map((type) {
        return DropdownMenuItem(
          value: type,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(type,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        );
      }).toList(),
      onChanged: onChange,
      // onChanged: (value) {
      //   final vehicleDoc = lstMonitorData[_tabController!.index];
      //   final docId = vehicleDoc.id;
      //
      //   setState(() {
      //     mapMonitorData[docId]?[SettingMonitorType] = value;
      //     _saveCurrentMonitor();
      //   });
      //},
    );
  }
}

Future<bool> _isWifiConnected(String ip, int port) async {
  try {
    final socket = await Socket.connect(ip, port, timeout: Duration(seconds: 2));
    socket.destroy();
    return true;   // Connected!
  } catch (e) {
    return false;  // Cannot reach Pi
  }
}
Future<bool> _mqttConnect(String ip) async {
  if (!await _isWifiConnected(ip, 1883)) {
    print("Wifi Fail");
    return false;
  }

  mqtt_Service.ipAdr = ip;
  await mqtt_Service.init();

  if (!await mqtt_Service.connect()) {
    MyGlobalSnackBar.show("MQTT Connection FAILED");
    return false;
  }

  MyGlobalSnackBar.show("Connected: $ip");
  return true;
}
Future<void> _mqttDisconnect()async{
  mqtt_Service.disconnect();
  MyGlobalSnackBar.show("Disconnected");
}

//---------------------------------------------------
// Services
//---------------------------------------------------
class UserData{
  String displayName = "";
  String surname = "";
  String userID = "";
  String email = "";
  String errorMsg = "";
  String photoURL = "";
  //bool isLoggedIn = false;
  bool hasError = false;
  bool emailValidated = false;

  UserData({
    this.displayName = "",
    this.surname = "",
    this.userID = "",
    this.email = "",
    this.errorMsg = "",
    this.photoURL = "",
    //this.isLoggedIn = false,
    this.emailValidated = false,
  });

  factory UserData.fromMap(Map<String, dynamic> map){
    return UserData(
      displayName: map['displayName'] ?? "",
      surname: map['surname'] ?? "",
      email: map['email'] ?? "",
      photoURL: map['photoURL'] ?? "",
      //isLoggedIn: map['isLoggedIn'] ?? false,
      emailValidated: map['emailValidated'] ?? false,
    );
  }
  Map<String, dynamic> toMap(){
    return{
      'displayName': displayName,
      'surname': surname,
      'email': email,
      'photoURL': photoURL,
      //'isLoggedIn': isLoggedIn,
      'emailValidated': emailValidated
    };
  }
  UserData copyWith({
    String? displayName,
    String? surname,
    String? email,
    String? photoURL,
    //bool? isLoggedIn,
    bool? emailValidated,
  }){
    return UserData(
      displayName: displayName ?? this.displayName,
      surname: surname ?? this.surname,
      email: email ?? this.email,
      photoURL: photoURL ?? this.photoURL,
      //isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      emailValidated: emailValidated ?? this.emailValidated,
    );
  }
}
class UserDataService extends ChangeNotifier {
  //static final UserDataService _instance = UserDataService._internal();
  //factory UserDataService() => _instance;
  //UserDataService._internal();

  UserData? _userdata;
  UserData? get userdata => _userdata;

  bool isLoading = false;
  bool isLoggedIn = false;
  bool firebaseError = false;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  UserDataService() {
    FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  Future<void> _onAuthChanged(User? user) async {

    if (user == null) {
      _userdata = null;
      isLoggedIn = false;
      isLoading = false;
      notifyListeners();
      return;
    }

    await load(); // automatically load Firestore user data
  }

  Future<void> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      firebaseError = true;
      isLoading = false;
      isLoggedIn = false;
      return;
    }

    isLoading = true;
    firebaseError = false;
    notifyListeners();

    final doc = await _db
        .collection(CollectionUsers)
        .doc(uid)
        .get();

    if (doc.exists) {
      _userdata = UserData.fromMap(doc.data()?[FieldsUserData] ?? {});
      _userdata?.userID = uid;
      _userdata?.emailValidated = FirebaseAuth.instance.currentUser!.emailVerified;
      isLoggedIn = true;
    } else {
      _userdata = null;
      isLoggedIn = false;
    }

    isLoading = false;
    notifyListeners();
  }
  Future<void> create(UserData newUserData, {required String uid}) async {
    _userdata = newUserData;

    try {
      await _db.collection(CollectionUsers).doc(uid).set({
        FieldsUserData: newUserData.toMap(),
      }, SetOptions(merge: true));

      notifyListeners();
    } catch (e) {
      print("Failed to save user data: $e");
    }
  }

  Future<void> updateFields(Map<String, dynamic> updates) async {
    try {
      final current = _userdata;
      if (current == null) return;

      final updated = current.copyWith(
        displayName: updates['displayName'] ?? current.displayName,
        surname: updates['surname'] ?? current.surname,
        email: updates['email'] ?? current.email,
        emailValidated: updates['emailValidated'] ?? current.emailValidated,
        //isLoggedIn: updates['isLoggedIn'] ?? current.isLoggedIn,
      );

      _userdata = updated;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Get only the keys that changed
      final Map<String, dynamic> nestedUpdates = {};
      updated.toMap().forEach((key, value) {
        if (updates.containsKey(key)) {
          nestedUpdates['$FieldsUserData.$key'] = value;
        }
      });

      await _db.collection(CollectionUsers).doc(uid).update(nestedUpdates);

      notifyListeners();
    } catch (e) {
      GlobalMsg.show('update Userdata Fields:', '$e');
    }
  }
  Future<void> logout() async{
    try{
      await _auth.signOut();
      await updateFields({'isLoggedIn': false});

      notifyListeners();
    }catch (e){
      GlobalMsg.show('Logout:', '$e');
    }
  }
  void printHash() {
    print(hashCode);
  }
}

class FireSettings{
  bool isVoicePromptOn;
  int logPointPerMeter;
  double rebateValuePerLiter;
  double dieselPrice;
  String connectedDevice;
  String connectedDeviceIp;
  List<ServerData>? serverData;

  FireSettings({
    required this.dieselPrice,
    required this.isVoicePromptOn,
    required this.logPointPerMeter,
    required this.rebateValuePerLiter,
    this.connectedDevice = "",
    this.connectedDeviceIp = "",
    this.serverData
  });

  factory FireSettings.fromMap(Map<String, dynamic> map){
    return FireSettings(
      isVoicePromptOn: map[SettingIsVoicePromptOn] ?? true,
      dieselPrice: map[SettingDieselPrice] ?? 20,
      logPointPerMeter: map[SettingLogPointPerMeter] ?? 10,
      rebateValuePerLiter: map[SettingRebateValue] ?? 2.6,
      connectedDevice: map[SettingConnectedDevice] ?? "",
      connectedDeviceIp: map[SettingConnectedDeviceIp] ?? "",
      serverData: map[SettingServerData] != null
        ? List<ServerData>.from(
        (map[SettingServerData] as List)
            .map((e) => ServerData.fromMap(e as Map<String, dynamic>)))
        : null,
    );
  }

  Map<String, dynamic> toMap(){
    return{
      SettingIsVoicePromptOn : isVoicePromptOn,
      SettingDieselPrice : dieselPrice,
      SettingLogPointPerMeter : logPointPerMeter,
      SettingRebateValue : rebateValuePerLiter,
      SettingConnectedDevice : connectedDevice,
      SettingConnectedDeviceIp : connectedDeviceIp,
      SettingServerData : serverData?.map((e) => e.toMap()).toList(),
    };
  }

  FireSettings copyWith({
    bool? isVoicePromptOn,
    int? logPointPerMeter,
    double? rebateValuePerLiter,
    double? dieselPrice,
    String? connectedDevice,
    String? connectedDeviceIp,
    List<ServerData>? serverData,
  }){
    return FireSettings(
      isVoicePromptOn: isVoicePromptOn ?? this.isVoicePromptOn,
      logPointPerMeter: logPointPerMeter ?? this.logPointPerMeter,
      dieselPrice: dieselPrice ?? this.dieselPrice,
      rebateValuePerLiter: rebateValuePerLiter ?? this.rebateValuePerLiter,
      connectedDevice: connectedDevice ?? this.connectedDevice,
      connectedDeviceIp: connectedDeviceIp ?? this.connectedDeviceIp,
      serverData: serverData ?? this.serverData,
    );
  }
}
class SettingsService extends ChangeNotifier {
  FireSettings? _settings;
  FireSettings? get fireSettings => _settings;

  bool isLoading = false;
  bool isConnecting = false;
  bool isBaseStationConnected = false;
  int monitorWheelDistance = 0;
  bool monitorWheelReset = false;
  bool monitorWheelSignal = false;
  String? lastConnectionError = "";

  final _db = FirebaseFirestore.instance;


  Future<void> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    isLoading = true;

    final doc = await _db
        .collection(CollectionUsers)
        .doc(uid)
        .get();

    if (doc.exists) {
      _settings = FireSettings.fromMap(doc.data()?[FieldsSettings] ?? {});
      notifyListeners();
    }

    isLoading = false;
  }
  Map<String, dynamic> flattenMap(Map<String, dynamic> map, [String prefix = '']) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      final newKey = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, dynamic>) {
        result.addAll(flattenMap(value, newKey));
      } else {
        result[newKey] = value;
      }
    });
    return result;
  }
  Future<void> updateFireSettingsFields(Map<String, dynamic> updates) async {
    try {
      // final current = _settings;
      // if (current == null) return;
      //
      // final updated = current.copyWith(
      //   isVoicePromptOn: updates[SettingIsVoicePromptOn] ?? current.isVoicePromptOn,
      //   logPointPerMeter: updates[SettingLogPointPerMeter] ?? current.logPointPerMeter,
      //   rebateValuePerLiter: updates[SettingRebateValue] ?? current.rebateValuePerLiter,
      //   dieselPrice: updates[SettingDieselPrice] ?? current.dieselPrice,
      //   connectedDevice: updates[SettingConnectedDevice] ?? current.connectedDevice,
      //   connectedDeviceIp: updates[SettingConnectedDeviceIp] ?? current.connectedDeviceIp,
      //   serverData: updates['serverData'] ?? current.serverData,
      // );
      //
      // _settings = updated;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final Map<String, dynamic> nestedUpdates = {};
      // updated.toMap().forEach((key, value) {
      //   if (updates.containsKey(key)) {
      //     nestedUpdates['$FieldsSettings.$key'] = value;
      //   }
      // });

      updates.forEach((key, value) {
        nestedUpdates['$FieldsSettings.$key'] = value;
      });

      await _db.collection(CollectionUsers)
          .doc(uid)
          .update(nestedUpdates);

      notifyListeners();

    } catch (e) {
      GlobalMsg.show('updateSettingFields:', '$e');
    }
  }

  void notify() => notifyListeners();

  Future<bool> mqttConnect(String ip) async {
    if (isConnecting) return true;
    if (isBaseStationConnected) return true;

    isConnecting = true;
    notifyListeners();

    try {
      if(await _mqttConnect(ip)){
        isBaseStationConnected = true;
        lastConnectionError = '';
      }
    } catch (e) {
      lastConnectionError = e.toString();
    } finally {
      isConnecting = false;
      notifyListeners();
    }

    if(!isBaseStationConnected){
      return false;
    }
    else {
      return true;
    }
  }
  Future<void> mqttDisconnect()async{
    await _mqttDisconnect();
    isBaseStationConnected = false;
    notifyListeners();
  }

  void update({
    bool? isBaseStationConnected,
  }) {
    bool changed = false;

    if (isBaseStationConnected != null && isBaseStationConnected != this.isBaseStationConnected) {
      this.isBaseStationConnected = isBaseStationConnected;
      changed = true;
    }

    if (changed){
      notifyListeners();
    }
  }
}
class ServerData {
  String? name;
  String? description;
  String? bluetooth;
  String? ipAddress;

  ServerData({
    this.name,
    this.description,
    this.bluetooth,
    this.ipAddress,
  });

  factory ServerData.fromMap(Map<String, dynamic> map) {
    return ServerData(
      name: map['name'],
      description: map['description'],
      bluetooth: map['bluetooth'],
      ipAddress: map['ipAddress'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'bluetooth': bluetooth,
      'ipAddress': ipAddress,
    };
  }
}

class MonitorSettings {

  // Persisted (Firebase) fields
  String monitorId;
  String? monitorType;
  String monitorName;
  String reg;
  double fuelConsumption;
  double rebateValue;
  String bluetoothDeviceName;
  String bluetoothMac;
  String image;
  double ticksPerM;

  // Local-only (NOT saved)
  bool isLoading;
  bool isConnectedToIot;
  bool isConnectingToIot;
  double wheelDistance;
  bool wheelSignal;
  String monDocId;
  String userDocId;

  MonitorSettings({
    // Firebase
    this.monitorId = "none",
    this.monitorType = MonTypeVehicle,
    this.monitorName = "New Item",
    this.reg = "none",
    this.fuelConsumption = 10,
    this.rebateValue = 10,
    this.bluetoothDeviceName = "",
    this.bluetoothMac = "",
    this.image = "",
    this.ticksPerM = 20,

    // Local
    this.isLoading = false,
    this.isConnectedToIot = false,
    this.isConnectingToIot = false,
    this.wheelDistance = 0,
    this.wheelSignal = false,
    this.monDocId = "",
    this.userDocId = "",
  });

  // From Firebase
  factory MonitorSettings.fromMap(Map<String, dynamic> map, String docId, String userId) {
    return MonitorSettings(
      monDocId: docId,
      userDocId: userId,
      monitorId: map[FIRE_MON_ID] ?? 'none',
      monitorType: map[FIRE_MON_TYPE] ?? 'none',
      monitorName: map[FIRE_MON_NAME] ?? 'New Item',
      reg: map[FIRE_MON_REGISTRATION] ?? 'None',
      fuelConsumption: (map[FIRE_MON_FUEL_CONSUMPTION] as num?)?.toDouble() ?? 0.0,
      //rebateValue: map[SettingRebateValue] ?? 0,
      bluetoothDeviceName: map[FIRE_MON_BT_NAME] ?? '',
      bluetoothMac: map[FIRE_MON_BT_MAC] ?? '',
      ticksPerM: (map[FIRE_MON_TICKS_PER_M] as num?)?.toDouble() ?? SettingMonDefaultTicksPerM,
      image: map[FIRE_MON_IMAGE] ?? '',
    );
  }

  // To Firebase (NO local fields)
  Map<String, dynamic> toMap() {
    return {
      FIRE_MON_ID: monitorId,
      FIRE_MON_TYPE: monitorType,
      FIRE_MON_NAME: monitorName,
      FIRE_MON_REGISTRATION: reg,
      FIRE_MON_FUEL_CONSUMPTION: fuelConsumption,
      SettingRebateValue: rebateValue,
      FIRE_MON_BT_NAME: bluetoothDeviceName,
      FIRE_MON_BT_MAC: bluetoothMac,
      FIRE_MON_TICKS_PER_M: ticksPerM,
      FIRE_MON_IMAGE: image
    };
  }
}
class MonitorSettingsService extends ChangeNotifier {
  final List<MonitorSettings> _monitors = [];
  MonitorSettings? _selected;
  bool isLoading = true;

  List<MonitorSettings> get lstMonitors => List.unmodifiable(_monitors);
  //MonitorSettings? get selected => _selected;

  Future<void> load() async {
    isLoading = true;
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionMonitors)
        .get();

    final list = snapshot.docs
        .map((doc) => MonitorSettings.fromMap(doc.data(),doc.id, uid))
        .toList();

    try {
      setMonitors(list);
    } catch (e) {
      print(e);
    } finally {
      isLoading = false;   // ✅ CLEAR HERE
      notifyListeners();   // ✅ NOTIFY HERE
    }
  }

  void notify() => notifyListeners();
  void setMonitors(List<MonitorSettings> list) {
    _monitors
      ..clear()
      ..addAll(list);
    notifyListeners();
  }
  void addMonitor(MonitorSettings mon) {
    _monitors.add(mon);
    notifyListeners();
  }
  void removeMonitor(String id) {
    _monitors.removeWhere((m) => m.monitorId == id);
    if (_selected?.monitorId == id) _selected = null;
    notifyListeners();
  }
  void selectMonitor(String id) {
    _selected = _monitors.firstWhere((m) => m.monitorId == id);
    notifyListeners();
  }

  // Local-only updates
  void setConnectedToIot(String id, bool value) {
    final mon = _monitors.firstWhere((m) => m.monitorId == id);
    mon.isConnectedToIot = value;
    notifyListeners();
  }
  void setConnectingToIot(String id, bool value) {
    final mon = _monitors.firstWhere((m) => m.monitorId == id);
    mon.isConnectingToIot = value;
    notifyListeners();
  }
}

class MonitorData {
  // General
  String monDocId;
  String userDocId;
  String? monitorType;
  String monitorName;

  // Tracking
  //String? reg;
  //double? distance_inside;
  //double? distance_outside;
  //String start_time;
  //String end_time;

  // Distance Wheel
  String? operator;
  String? supervisor;
  double? distance;
  int? lines;
  Timestamp timestamp;

  // Local-only (NOT saved)
  bool isLoading = false;

  MonitorData({
    required this.monDocId,
    required this.userDocId,
    required this.monitorName,
    required this.monitorType,

    // Tracking
    //this.reg = "",
    //this.distance_inside = 0,
    //this.distance_outside = 0,
    //this.start_time = "",
    //this.end_time = "",

    // Wheel
    this.operator = "",
    this.supervisor = "",
    this.distance = 0,
    this.lines = 0,
    required this.timestamp,
  });

  // From Firebase
  factory MonitorData.fromDoc(DocumentSnapshot doc) {
    final map = doc.data() as Map<String, dynamic>;

    return MonitorData(
      monDocId: map[LogMonDocId],
      userDocId: map[LogMonUserDocId],
      monitorType: map[LogMonType],
      monitorName: map[LogMonName],
      operator: map[LogMonOperator] ?? '',
      supervisor: map[LogMonSupervisor] ?? '',
      distance: (map[LogMonDistance] as num?)?.toDouble() ?? 0,
      lines: (map[LogMonLines] as num?)?.toInt() ?? 0,
      timestamp: map[LogMonTimestamp],
    );
  }
}
class MonitorDataService extends ChangeNotifier {
  String monDocId;
  String? monitorType;
  String monitorName;
  String image;
  String reg;
  List<MonitorData> lstMonitorData = [];

  // Local
  bool isLoading = true;

  MonitorDataService({
    required this.monDocId,
    required this.monitorType,
    required this.monitorName,
    this.reg = "",
    this.image = '',
    required this.lstMonitorData
  });


  Future<MonitorDataService> fromSnapshot( DocumentSnapshot monitorSnapshot) async {
    isLoading = true;
    final map = monitorSnapshot.data() as Map<String, dynamic>;

    // IOT Data - subcollection
    final dataSnapshot = await monitorSnapshot.reference
        .collection(CollectionMonitorData)
        .get();

    final dataList = dataSnapshot.docs
        .map((doc) => MonitorData.fromDoc(doc))
        .toList();

    isLoading = false;

    return MonitorDataService(
      monDocId : monitorSnapshot.id,
      monitorType: map[FIRE_MON_TYPE] ?? '',
      monitorName: map[FIRE_MON_BT_NAME] ?? '',
      lstMonitorData: dataList,
    );
  }
}

class BaseStationData {

  // Persisted (Firebase) fields
  String baseName;
  String baseDesc;
  String ipAddress;
  String bluetoothName;
  String bluetoothMac;
  String image;

  // Local-only (NOT saved)
  bool isLoading;
  bool isConnected;
  String docId;

  BaseStationData({
    // Firebase
    this.baseName = "New Base",
    this.baseDesc = "none",
    this.ipAddress = "0:0:0:0",
    this.bluetoothName = "",
    this.bluetoothMac = "",
    this.image = "",

    // Local
    this.isLoading = false,
    this.isConnected = false,
    this.docId = ""
  });


  // From Firebase
  factory BaseStationData.fromMap(Map<String, dynamic> map, String docId) {
    return BaseStationData(
      docId: docId,
      baseName: map[FIRE_BASE_NAME] ?? 'none',
      baseDesc: map[FIRE_BASE_DESC] ?? 'none',
      ipAddress: map[FIRE_BASE_IP] ?? 'New Item',
      bluetoothName: map[FIRE_BASE_BT_NAME] ?? 'None',
      bluetoothMac: map[FIRE_MON_BT_MAC] ?? '',
      image: map[FIRE_BASE_IMAGE] ?? '',
    );
  }

  // To Firebase (NO local fields)
  Map<String, dynamic> toMap() {
    return {
      FIRE_BASE_NAME : baseName,
      FIRE_BASE_DESC : baseDesc,
      FIRE_BASE_IP : ipAddress,
      FIRE_BASE_BT_NAME : bluetoothName,
      FIRE_BASE_BT_MAC : bluetoothMac,
      FIRE_BASE_IMAGE: image
    };
  }
}
class BaseStationService extends ChangeNotifier {
  final List<BaseStationData> _base = [];
  BaseStationData? _selected;
  bool isLoading = true;

  List<BaseStationData> get lstBaseStations => List.unmodifiable(_base);
  BaseStationData? get selected => _selected;

  Future<void> load() async {
    isLoading = true;

    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionServers)
        .get();

    final list = snapshot.docs
        .map((doc) => BaseStationData.fromMap(doc.data(), doc.id))
        .toList();

    try {
      if (lstBaseStations.length != list.length) {
        setBaseStations(list);
      }
    } catch (e) {
      print(e);
    } finally {
      isLoading = false;   // ✅ CLEAR HERE
      notifyListeners();   // ✅ NOTIFY HERE
    }
  }

  void setBaseStations(List<BaseStationData> list) {
    _base
      ..clear()
      ..addAll(list);
    notifyListeners();
  }
  void addBaseStations(BaseStationData newBase) {
    _base.add(newBase);
    notifyListeners();
  }
  void removeBaseStations(String id) {
    _base.removeWhere((m) => m.docId == id);
    if (_selected?.docId == id) _selected = null;
    notifyListeners();
  }
  void selectMonitor(String id) {
    _selected = _base.firstWhere((m) => m.docId == id);
    notifyListeners();
  }
  void setConnectedByIp(String ip, bool value) {
    final base = lstBaseStations.firstWhereOrNull((b) => b.ipAddress == ip);
    if (base == null) return;

    base.isConnected = value;
    notifyListeners();
  }
  void setIpAddress(BaseStationData base, String value) {
    base.ipAddress = value;
    notifyListeners();
  }
}

//---------------------------------------------------
// Widgets
//---------------------------------------------------
Widget ShowWelcomeMsg(BuildContext context) {
  UserDataService user = context.read<UserDataService>();

  if (user.isLoggedIn) {
    return Text(
      'Welcome ${user.userdata!.displayName}',
      style: const TextStyle(
        color: Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  } else {
    return const Text(
      'Please login to continue',
      style: TextStyle(
        color: Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
Widget MyIcons(String text, IconData icon, GestureTapCallback onTap){
  return
    GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.all(5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 40,
              color: Colors.blue,
            ),

            SizedBox(height: 5),

            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.blue
              ),
            ),
          ],
        ),
        ),
    );
}
Widget MyAppbarTitle(String text){
  return Center(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.normal,
            fontSize: 22,
            color: Colors.grey
            ),
        ),
      ],
    ),
  );
}
LinearGradient MyTileGradient() {
  return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: [
      0.1,
      0.3,
      0.7,
      ],
      colors: [
        APP_TILE_COLOR,
        APP_BACKGROUND_COLOR,
        APP_TILE_COLOR,
      ],
  );
}
LinearGradient MyTileGradientBlue() {
  return const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [
      0.1,
      0.9
    ],
    colors: [
      COLOR_BLUE,
      Colors.black,
    ],
  );
}
Widget MyProgressCircle() {
  return Center(
      child: CircularProgressIndicator(
          color: PROGRESS_CIRCLE_COLOR
      )
  );
}

//---------------------------------------------------
// Styles
//---------------------------------------------------
ButtonStyle MyButtonStyle(Color backgroundColor) {
  return TextButton.styleFrom(
    minimumSize: ui.Size(100, 30),
    backgroundColor: backgroundColor,
    shadowColor: Colors.white,
  );
}
TextStyle MyTextStyle(){
  double fontsize = 16;

  return TextStyle(
      color: Colors.white,
      fontSize: fontsize,
      fontWeight: FontWeight.normal,
      fontFamily: "Poppins"
  );
}

