import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geofence/firebase.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geofence/utils.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool isDebug = true;
String debugLog = '';

//Variant: debugAndroidTest
//Config: debug
//Store: C:\Users\mradyn\.android\debug.keystore
//Alias: AndroidDebugKey
//MD5: 87:9C:BF:70:DB:3E:04:A9:FE:AB:34:70:06:BE:FA:A3
//SHA1: 79:03:DE:0A:58:43:3B:9D:39:F4:48:04:CB:25:8E:48:9D:D8:79:88
//SHA-256: C5:71:BA:B9:AC:78:67:EB:2C:D9:42:CB:38:3B:ED:9B:FB:07:01:13:81:7A:44:EB:25:26:A3:ED:AA:39:4D:54
//Valid until: Friday, 03 October 2053

const String  googleAPiKey ="AIzaSyAVDoWELQE16C0wkf7-FSzUywpEcI6sYOc";

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
const APP_BACKGROUND_COLOR = Color.fromARGB(255, 0, 24, 37);
const APP_TILE_COLOR = Color.fromARGB(255, 21, 34, 52);
const DRAWER_COLOR = Color.fromARGB(255, 33, 137, 215);

final FirebaseAuthService firebaseAuthService = FirebaseAuthService();
final FirebaseFirestore firestore = FirebaseFirestore.instance;

final String fireUserName = 'user1';
final String fireUserRecyclebin = '${fireUserName}_recycle/';
const String DB_TABLE_USERS = 'UserTable';

final String iconWARNING = "assets/warning.png";
final String iconGOOGLE = 'assets/google_icon.png';
final String iconFACEBOOK = 'assets/facebook_icon.png';
final String picPROFILE = 'assets/profile.png';

//---------------------------------------------------
// Firebase Settings
//---------------------------------------------------
const CollectionUsers = 'users';
const CollectionGeoFences = 'geofences';
const CollectionTrackingSessions = 'tracking_sessions';
const CollectionLocations = 'locations';
const CollectionVehicles = 'vehicles';
const CollectionSettings = 'settings';

const DocAppSettings = 'app_settings';

const SettingIsVoicePromptOn = 'isVoicePromptOn';
const SettingLogPointPerMeter = 'logPointPerMeter';


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
  if(kIsWeb) return true;
  else return false;
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
void myMessageBox (BuildContext context, String message) {

  showDialog(
    context: context,
    barrierDismissible: false, // Prevents accidental closing
    builder: (context) => _myMessageBox(message: message),
  );
}
class _myMessageBox extends StatelessWidget {
  final String message;
  final String header;
  final String image;

  const _myMessageBox({
    required this.message,
    this.header = "Warning",
    this.image = "assets/warning.png",
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
        side: const BorderSide(
          color: Colors.blue, // Border color
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
                  fontsize: 20,
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
                fontsize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class MyTextFormField extends StatefulWidget {
  final TextEditingController? controller;
  final Key? key;
  final bool? isPasswordField;
  final String? hintText;
  final String? labelText;
  final String? helperText;
  final FormFieldSetter<String>? onSaved;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputType? inputType;
  final double? width;

  const MyTextFormField({
    this.controller,
    this.isPasswordField,
    this.key,
    this.hintText,
    this.labelText,
    this.helperText,
    this.onSaved,
    this.validator,
    this.width,
    this.onFieldSubmitted,
    this.inputType
  });

  @override
  _MyTextFormFieldState createState() => _MyTextFormFieldState();
}
class _MyTextFormFieldState extends State<MyTextFormField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      //clipBehavior: Clip.hardEdge,
      //decoration: BoxDecoration(
      //  borderRadius: BorderRadius.circular(4),
      color: Colors.red,
      //),
      child: TextFormField(
        style: TextStyle(
            fontSize: 14,
            color: Colors.black
        ),
        controller: widget.controller,
        keyboardType: widget.inputType,
        key: widget.key,
        obscureText: widget.isPasswordField == true ? _obscureText : false,
        onSaved: widget.onSaved,
        validator: widget.validator,
        onFieldSubmitted: widget.onFieldSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          filled: true,
          hintText: widget.hintText,
          hintStyle: TextStyle(
              color: Colors.blueGrey
          ),
          suffixIcon: GestureDetector(
            onTap: () {
              setState(() {
                _obscureText = !_obscureText;
              });
            },
            child: widget.isPasswordField == true
                ? Icon(
              _obscureText ? Icons.visibility_off : Icons.visibility,
              color: _obscureText == false ? Colors.blue : Colors.grey,
            )
                : Text(""),
          ),
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
  String image;

  MyDialogWidget({
    super.key,
    required this.message,
    required this.header,
    required this.but1Text,
    required this.but2Text,
    this.onPressedBut1,
    this.onPressedBut2,
    this.image = "assets/images/warning.png",
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Row(
        children: [
          Expanded(flex: 1, child: Image.asset(image, height: 30, width: 30)),
          SizedBox(width: 20),
          Expanded(flex: 4, child: Text(header, textAlign: TextAlign.start)),
        ],
      ),
      content: Text(message, textAlign: TextAlign.center),
      actions: <Widget>[
        TextButton(
          style: TextButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          onPressed: onPressedBut1,
          child: Text(but1Text),
        ),
        TextButton(
          style: TextButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          onPressed: onPressedBut2,
          child: Text(but2Text),
        ),
      ],
    );
  }
}
class myCustomTileWithPic extends StatelessWidget {
  final String imagePath;
  final String header;
  final String description;
  final Widget widget;

  const myCustomTileWithPic({
    required this.imagePath,
    required this.header,
    this.description = "",
    required this.widget,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    final _userData = Provider.of<UserData>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.only(top: 5, bottom: 5),
      child: Center(
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
            borderRadius:const BorderRadius.only(
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            border: Border.all(
              color: Colors.grey,
              width: 2,
            )
          ),
          child:
            GestureDetector(
              onTap: (){
                if(_userData.isLoggedIn){
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => widget),
                  );
                }else{
                  myMessageBox(context, "User not Logged In");
                }
              },
              child: Row(
                children: [
                  // Image
                  Image.asset (
                      imagePath,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover
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

              SizedBox(height: 1),

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
class MyTextOption extends StatelessWidget {
  TextEditingController controller = TextEditingController();
  String label;
  String description;
  String measure;

  MyTextOption({
    required this.controller,
    required this.label,
    this.description = "",
    this.measure = "",
  });

  @override
  Widget build(BuildContext context) {
    return  Padding(
      padding: const EdgeInsets.only(left: 10.0, right: 10, bottom: 5),
      child: Container(
        padding: EdgeInsets.only(top: 10, bottom: 10,left: 15),
        decoration: BoxDecoration(
          gradient: MyTileGradient(),
          border: Border.all(
            color: Colors.grey,
            width: 1
          ),
          borderRadius: BorderRadius.circular(8),
        ),
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
                decoration: const InputDecoration(
                  hintText: '0',
                  border: OutlineInputBorder(),
                  suffixText: "m",
                  suffixStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 18
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
        decoration: BoxDecoration(
          gradient: MyTileGradient(),
          border: Border.all(
              color: Colors.grey,
              width: 1
          ),
          borderRadius: BorderRadius.circular(8),
        ),
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
      style: TextStyle(
        color: color,
        fontFamily: 'Poppins',
        fontWeight: FontWeight.normal,
        fontSize: fontsize,
      ),
    );
  }
}
class MyTextTileWithEditDelete extends StatelessWidget {
  final String text;
  final String subtext;
  final Function? onTapEdit;
  final Function? onTapDelete;
  final Function? onTapTile;

  const MyTextTileWithEditDelete({
    required this.text,
    required this.subtext,
    this.onTapEdit,
    this.onTapDelete,
    this.onTapTile,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (){
        if(onTapTile != null)
          onTapTile!();
        },
      child: Container(
        decoration: BoxDecoration(
          color: APP_TILE_COLOR,
          border: Border.all(
            color: Colors.grey,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(5),
          gradient: MyTileGradient(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MyText(
                      text: text,
                      color: Colors.white,
                      fontsize: 18,
                    ),
                    SizedBox(height: 1),

                    MyText(
                      text: subtext,
                      color: Colors.grey,
                      fontsize: 14,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if(onTapEdit != null)
                  IconButton(
                    icon: Icon(Icons.edit, color: Colors.white,),
                    onPressed: () => onTapEdit!(),
                    iconSize: 25,
                    constraints: BoxConstraints(),
                  ),

                if(onTapDelete != null)
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red,),
                    onPressed: () => onTapDelete!(),
                    iconSize: 25,
                    constraints: BoxConstraints(),
                  ),
              ],
            ),
          ],
        ),
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
class GlobalSnackBar {
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

//---------------------------------------------------
// Data Services
//---------------------------------------------------
class UserData{
  String displayName = "";
  String surname = "";
  String userID = "";
  String? email = "";
  String errorMsg = "";
  String photoURL = "";
  bool isLoggedIn = false;
  bool emailValidated = false;

  UserData({
    this.displayName = "",
    this.surname = "",
    this.userID = "",
    this.email = "",
    this.errorMsg = "",
    this.photoURL = "",
    this.isLoggedIn = false,
    this.emailValidated = false,
  });

  factory UserData.fromMap(Map<String, dynamic> map){
    return UserData(
      displayName: map['displayName'] ?? "",
      surname: map['surname'] ?? "",
      userID: map['userID'] ?? 0,
      email: map['email'] ?? "",
      photoURL: map['photoURL'] ?? "",
      isLoggedIn: map['isLoggedIn'] ?? false,
      emailValidated: map['emailValidated'] ?? false,
    );
  }

  Map<String, dynamic> toMap(){
    return{
      'displayName': displayName,
      'surname': surname,
      'userID': userID,
      'email': email,
      'photoURL': photoURL,
      'isLoggedIn': isLoggedIn,
      'emailValidated': emailValidated
    };
  }

  UserData copyWith({
    String? displayName,
    String? surname,
    String? userID,
    String? email,
    String? photoURL,
    bool? isLoggedIn,
    bool? emailValidated,
  }){
    return UserData(
      displayName: displayName ?? this.displayName,
      surname: surname ?? this.surname,
      userID: userID ?? this.userID,
      email: email ?? this.email,
      photoURL: photoURL ?? this.photoURL,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      emailValidated: emailValidated ?? this.emailValidated,
    );
  }
}
class UserDataService extends ChangeNotifier {
  static final UserDataService _instance = UserDataService._internal();
  factory UserDataService() => _instance;
  UserDataService._internal();

  UserData? _userdata;
  UserData? get userdata => _userdata;
  bool isLoading = false;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Future<void> load() async {
    if(_auth == null) return;
    if(_db == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    isLoading = true;

    final doc = await _db
        .collection(CollectionUsers)
        .doc(uid)
        .get();

    if (doc.exists) {
      _userdata = UserData.fromMap(doc.data()?[CollectionSettings] ?? {});
      notifyListeners();
    }

    isLoading = false;
  }
  Future<void> update(UserData newUserData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _userdata = newUserData;
    await _db.collection(CollectionUsers).doc(uid).update({
      CollectionSettings : newUserData.toMap(),
    });

    notifyListeners();
  }
  Future<void> updateFields(Map<String, dynamic> updates) async {
    try {
      final current = _userdata;
      if (current == null) return;

      final updated = current.copyWith(
        displayName: updates['displayName'] ?? current.displayName,
        surname: updates['surname'] ?? current.surname,
        userID: updates['userID'] ?? current.userID,
        email: updates['email'] ?? current.email,
        emailValidated: updates['emailValidated'] ?? current.emailValidated,
        isLoggedIn: updates['isLoggedin'] ?? current.isLoggedIn,
      );

      _userdata = updated;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await _db.collection(CollectionUsers).doc(uid).update({
        CollectionSettings: updated.toMap(),
      });

      notifyListeners();
    } catch (e) {
      GlobalMsg.show('update Userdata Fields:', '${e}');
    }
  }
  Future<void> logout() async{
    try{
      await _auth.signOut();
      await updateFields({'isLoggedIn': false});

      notifyListeners();
    }catch (e){
      GlobalMsg.show('Logout:', '${e}');
    }
  }
  void printHash() {
    print(this.hashCode);
  }
}

class Settings{
  bool isVoicePromptOn;
  int logPointPerMeter;
  double rebateValuePerLiter;
  double dieselPrice;

  Settings({
    required this.dieselPrice,
    required this.isVoicePromptOn,
    required this.logPointPerMeter,
    required this.rebateValuePerLiter
  });

  factory Settings.fromMap(Map<String, dynamic> map){
    return Settings(
      isVoicePromptOn: map['isVoicePromptOn'] ?? true,
      dieselPrice: map['dieselPrice'] ?? 20,
      logPointPerMeter: map['logPointPerMeter'] ?? 10,
      rebateValuePerLiter: map['rebatePerLiter'] ?? 2.6,
    );
  }

  Map<String, dynamic> toMap(){
    return{
      'isVoicePromptOn': isVoicePromptOn,
      'dieselPrice': dieselPrice,
      'logPointPerMeter': logPointPerMeter,
      'rebateValuePerLiter': rebateValuePerLiter
    };
  }

  Settings copyWith({
    bool? isVoicePromptOn,
    int? logPointPerMeter,
    double? rebateValuePerLiter,
    double? dieselPrice,
  }){
    return Settings(
      isVoicePromptOn: isVoicePromptOn ?? this.isVoicePromptOn,
      logPointPerMeter: logPointPerMeter ?? this.logPointPerMeter,
      dieselPrice: dieselPrice ?? this.dieselPrice,
      rebateValuePerLiter: rebateValuePerLiter ?? this.rebateValuePerLiter,
    );
  }
}
class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  Settings? _settings;
  Settings? get settings => _settings;
  bool isLoading = false;

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
      _settings = Settings.fromMap(doc.data()?[CollectionSettings] ?? {});
      notifyListeners();
    }

    isLoading = false;
  }
  Future<void> update(Settings newSettings) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _settings = newSettings;
    await _db.collection(CollectionUsers).doc(uid).update({
      CollectionSettings : newSettings.toMap(),
    });

    notifyListeners();
  }
  Future<void> updateFields(Map<String, dynamic> updates) async {
    try {
      final current = _settings;
      if (current == null) return;

      final updated = current.copyWith(
        isVoicePromptOn: updates['isVoicePromptOn'] ?? current.isVoicePromptOn,
        logPointPerMeter: updates['logPointPerMeter'] ?? current.logPointPerMeter,
        rebateValuePerLiter: updates['rebateValuePerLiter'] ?? current.rebateValuePerLiter,
        dieselPrice: updates['dieselPrice'] ?? current.dieselPrice,
      );

      _settings = updated;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await _db.collection(CollectionUsers).doc(uid).update({
        CollectionSettings: updated.toMap(),
      });

      notifyListeners();
    } catch (e) {
      GlobalMsg.show('updateSettingFields:', '${e}');
    }
  }
}

//---------------------------------------------------
// Widgets
//---------------------------------------------------
Widget ShowWelcomeMsg(BuildContext context) {
  final _userData = Provider.of<UserData>(context, listen: false);

  if (_userData.isLoggedIn) {
    return Text(
      'Welcome ${_userData.displayName}',
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
      0.7,
      0.9,
      ],
      colors: [
      Colors.black,
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

//---------------------------------------------------
// Styles
//---------------------------------------------------
ButtonStyle MyButtonStyle(Color backgroundColor) {
  return TextButton.styleFrom(
    minimumSize: const Size(100, 50),
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