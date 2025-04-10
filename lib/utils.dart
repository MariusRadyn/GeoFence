import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geofence/firebase.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geofence/utils.dart';

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
FenceData fenceData = FenceData();

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
const CollectionTracking = 'tracking_sessions';
const CollectionVehicles = 'vehicles';
const CollectionSettings = 'settings';

const DocAppSettings = 'app_settings';

const SettingIsVoicePromptOn = 'IsVoicePromptOn';
const SettingLogPointPerMeter = 'LogPointPerMeter';


//---------------------------------------------------
// Methods
//---------------------------------------------------
void printMsg(String msg) {
  if (isDebug) print(msg);
}
void writeLog(var text) {
  debugLog += text +'\r';
}
bool isPointInsidePolygon(Point test, List<Point> polygon) {
  int intersections = 0;
  int n = polygon.length;

  for (int i = 0; i < n; i++) {
    Point p1 = polygon[i];
    Point p2 = polygon[(i + 1) % n]; // Connect last point to first

    // Check if test point is exactly on a vertex (edge case)
    if ((test.x == p1.x && test.y == p1.y) || (test.x == p2.x && test.y == p2.y)) {
      return true;
    }

    // Check if the test point is within the y-range of the edge
    if ((test.y > min(p1.y, p2.y)) && (test.y <= max(p1.y, p2.y)) &&
        (test.x <= max(p1.x, p2.x))) {

      // Compute intersection point of polygon edge with horizontal ray
      double xIntersect = (test.y - p1.y) * (p2.x - p1.x) / (p2.y - p1.y) + p1.x;

      // If the intersection point is to the right of the test point, count it
      if (xIntersect > test.x) {
        intersections++;
      }
    }
  }

  // Odd intersections mean inside, even means outside
  print("Intersertions = $intersections");
  return (intersections % 2 == 1);
}
bool isOnDesktop() {
  if(kIsWeb) return true;
  else return false;
}
void MyMessageBox (BuildContext context, String message) {
  // Close any open dialogs first
  //if (Navigator.of(context).canPop()) {
  //  Navigator.of(context).pop();
  //}

  showDialog(
    context: context,
    barrierDismissible: false, // Prevents accidental closing
    builder: (context) => _myMessageBox(message: message),
  );
}

//---------------------------------------------------
// Class
//---------------------------------------------------
class GlobalSnackBar {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
  GlobalKey<ScaffoldMessengerState>();

  static void show(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.white,
      ),
    );
  }
}
class Point {
  final double x, y;
  Point(this.x, this.y);
}
class FenceData{
  String polygonId = "";
  String firestoreId = "";
  String name = "";
  List<LatLng> points = [];
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
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
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
                icon: Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // Heading with Image
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(image, height: 30, width: 30),
                SizedBox(width: 8),
                Text(
                  header,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 10),

            // Message
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                message,
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 20),

            // OK Button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
              },
              child: const Text(
                "OK",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class MyTextTile extends StatelessWidget {
  final Color? color;
  final String text;

  const MyTextTile({super.key, this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(50, 50, 50, 50),
      child: Container(
        color: color,
        child: Center(
          child: Column(
            children: [
              Text(
                text,
                style: const TextStyle(color: Colors.black, fontSize: 20),
              ),
              TextButton(
                  onPressed: () {Navigator.pop(context);
                  },
                  child: Container(
                    color: Colors.blue,
                    height: 20,
                    width: 100,
                    child: Center(
                        child: Text('OK')
                    ),
                    
                  ))
            ],
          ),
        ),
      ),
    );
  }
}
class MyLoginBox {
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  void Dispose() {
    _pwController.dispose();
    _emailController.dispose();
  }

  Future<void> dialogBuilder(BuildContext context, UserData _userData) {
    double _widthMedia = MediaQuery.of(context).size.width;
    double _heightMedia = MediaQuery.of(context).size.height;
    double _widthContainer = _widthMedia * 0.8;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Container(
              margin: const EdgeInsets.only(top: 20, bottom: 50),
              width:
              _widthContainer > 500 ? 500 : _widthContainer, // Custom width

              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Heading
                    const Text(
                      "Login",
                      textAlign: TextAlign.center,
                      style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 10),

                    // Email
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 20,
                          right: 20
                      ),
                      child: MyTextFormField(
                        controller: _emailController,
                        hintText: "Email Address",
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Password
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 20,
                          right: 20
                      ),
                      child: MyTextFormField(
                        controller: _pwController,
                        hintText: "Password",
                        isPasswordField: true,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Cancel Button
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: MyButtonStyle(COLOR_ORANGE),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.normal),
                            textAlign: TextAlign.right,
                          ),
                        ),

                        const SizedBox(width: 10),

                        // OK Button
                        TextButton(
                          onPressed: () {
                            loginWithEmail(context);
                          },
                          style: MyButtonStyle(COLOR_ORANGE),
                          child: const Text(
                            "OK",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.normal),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Register
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text("Dont have an account?"),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          MySignupBox().dialogBuilder(context);
                        },
                        child: const Text(
                          "Register",
                          style: TextStyle(color: COLOR_ORANGE),
                        ),
                      ),
                    ]),

                    SizedBox(height: 20),

                    // Login with Google
                    Container(
                      margin: MediaQuery.of(context).size.width > 600
                          ? const EdgeInsets.only(left: 110, right: 110)
                          : const EdgeInsets.only(left: 30, right: 30),
                      child: TextButton(
                        onPressed: () {
                          loginWithGoogle(context, _userData);
                        },
                        style: MyButtonStyle(Colors.white),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(iconGOOGLE, height: 30, width: 30),
                              SizedBox(width: 10),
                              const Text(
                                "Sign in with Google",
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal),
                                textAlign: TextAlign.center,
                              ),
                            ]),
                      ),
                    ),

                    SizedBox(height: 20),

                    // Signin with facebook
                    Container(
                      margin: MediaQuery.of(context).size.width > 600
                          ? const EdgeInsets.only(left: 110, right: 110)
                          : const EdgeInsets.only(left: 30, right: 30),
                      child: TextButton(
                        onPressed: () {
                          //loginWithGoogle(context);
                        },
                        style: MyButtonStyle(Colors.white),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            //mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(iconFACEBOOK, height: 30, width: 30),
                              SizedBox(width: 10),
                              const Text(
                                "Sign in with Facebook",
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal),
                                textAlign: TextAlign.center,
                              ),
                            ]),
                      ),
                    ),
                  ]
              ),
            )
        );
      },
    );
  }

  void loginWithEmail(BuildContext context) async {
    final _userData = Provider.of<UserData>(context, listen: false);

    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      MyMessageBox(context, 'Please enter both email and password');
      return;
    }

    if (!_emailController.text.contains('@')) {
      MyMessageBox(context, 'Please enter a valid email address.');
      return;
    }

    // Show status indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      User? user = await firebaseAuthService.fireAuthSignIn(
        context,
          _emailController.text,
          _pwController.text);

      // Pop status indicator
      Navigator.of(context).pop();

      if (user != null) {
        firebaseAuthService.updateDisplayName("Marius");
        _userData.update(user);

        printMsg('User logged in');
        Navigator.of(context).pop();
      } else {
        _userData.logout();
        printMsg(_userData.errorMsg);
        MyMessageBox(context, _userData.errorMsg);
      }
    } catch (e) {
      // Pop status indicator
      Navigator.of(context).pop();
      printMsg('Error: $e');
    }
  }
  void loginWithGoogle(BuildContext context, UserData _userData) async {
    bool showError = false;
    //final _userData = Provider.of<UserData>(context, listen: false);

    try {
      _userData.Clear();
      UserCredential? userCred = await firebaseAuthService.signInWithGoogle();

      if (userCred.user?.emailVerified != null) {
        _userData.update(userCred.user!);

        printMsg('User logged in with Google');
        _userData.printHash();

      } else {
        _userData.logout();
        printMsg(_userData.errorMsg);

        MyMessageBox(context, _userData.errorMsg);
      }
    } catch (e) {
      printMsg('Sign in With Google Error: $e');
      showError = true;
      _userData.errorMsg = e.toString();
    } finally {
      Navigator.of(context).pop();

      if (showError) {
        MyMessageBox(context, _userData.errorMsg);
      }
    }
  }
}
class MySignupBox {
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _pwController2 = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _userController = TextEditingController();

  void Dispose() {
    _pwController.dispose();
    _pwController2.dispose();
    _emailController.dispose();
    _userController.dispose();
  }

  Future<void> dialogBuilder(BuildContext context) {
    double _width = MediaQuery.of(context).size.width * 0.8;
    double _height = MediaQuery.of(context).size.height * 0.6;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: SizedBox(
              width: _width > 500 ? 500 : _width, // Custom width
              height: _height > 600 ? 600 : _height, // Custom height

              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Heading
                    Text(
                      "Sign Up",
                      textAlign: TextAlign.center,
                      style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),

                    SizedBox(height: 10),

                    // Username
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: MyTextFormField(
                        controller: _userController,
                        hintText: "Enter Username",
                      ),
                    ),

                    SizedBox(height: 20),

                    // Email
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: MyTextFormField(
                        controller: _emailController,
                        hintText: "Enter Email Address",
                      ),
                    ),

                    SizedBox(height: 20),

                    // Password 1
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: MyTextFormField(
                        controller: _pwController,
                        hintText: "Password",
                        isPasswordField: true,
                      ),
                    ),

                    SizedBox(height: 20),

                    // Password 2
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: MyTextFormField(
                        controller: _pwController2,
                        hintText: "Confirm Password",
                        isPasswordField: true,
                      ),
                    ),

                    SizedBox(height: 20),

                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Cancel Button
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: MyButtonStyle(COLOR_ORANGE),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.normal),
                            textAlign: TextAlign.right,
                          ),
                        ),

                        SizedBox(width: 10),

                        // OK Button
                        TextButton(
                          onPressed: () {
                            signUp(context);
                          },
                          style: MyButtonStyle(COLOR_ORANGE),
                          child: const Text(
                            "OK",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.normal),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ]),
            ));
      },
    );
  }

  void signUp(BuildContext context) async {
    final _userData = Provider.of<UserData>(context, listen: false);
    context.read<UserData>();

    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      MyMessageBox(context, 'Please enter both email and password.');
      return;
    }

    if (!_emailController.text.contains('@')) {
      MyMessageBox(context, 'Please enter a valid email address.');
      return;
    }

    if (_userController.text.isEmpty) {
      MyMessageBox(context,'Please enter Username.');
      return;
    }

    if (_pwController.text != _pwController2.text) {
      MyMessageBox(context, 'Passwords don''t match.');
      return;
    }

    // Show status indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      User? user = await firebaseAuthService.fireAuthCreateUser(
        context,
          _emailController.text,
          _pwController.text);

      // Pop status indicator
      Navigator.of(context).pop();

      if (user != null) {
        if (user.displayName != null) {
          //user. = _userController.text;
        }
        _userData.update(user);

        print('User Created');
        Navigator.of(context).pop();
      } else {
        _userData.logout();
        print(_userData.errorMsg);
        MyMessageBox(context, _userData.errorMsg);
      }
    } catch (e) {
      // Pop status indicator
      Navigator.of(context).pop();
      print('Error: $e');
    }
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
                  MyMessageBox(context, "User not Logged In");
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
class MyVehicleTile extends StatelessWidget {
  final String text;
  final String subtext;
  final Function? onTapEdit;
  final Function? onTapDelete;

  const MyVehicleTile({
    required this.text,
    required this.subtext,
    this.onTapEdit,
    this.onTapDelete,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.normal,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.start,
                  ),

                  SizedBox(height: 1),

                  Text(
                    subtext,
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
          ),

          SizedBox(width: 10,),
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
    );
  }
}


//---------------------------------------------------
// Data Providers
//---------------------------------------------------
class UserData extends ChangeNotifier {
  String displayName = "";
  String surname = "";
  String userID = "";
  String? email = "";
  String errorMsg = "";
  String photoURL = "";
  bool isLoggedIn = false;
  bool emailValidated = false;

  void update(User user) {
    try{
      if(user == null){
        userID = '';
        email = '';
        emailValidated = false;
        displayName = '';
        photoURL = "";
        isLoggedIn = false;
      }else{
        userID = user.uid;
        email = user.email;
        emailValidated = user.emailVerified;
        displayName = user.displayName ?? "";
        photoURL = user.photoURL ?? "";
        isLoggedIn = true;

        notifyListeners();
        print("Notify Listeners: UserData");
      }
    }catch (e){
      print(e);
    }

  }
  void printHash() {
    print(this.hashCode);
  }
  void logout() {
    userID = "";
    email = "";
    photoURL = "";
    isLoggedIn = false;
    emailValidated = false;
    displayName = "";
    notifyListeners();
  }
  void Clear() {
    displayName = "";
    surname = "";
    userID = "";
    email = "";
    errorMsg = "";
    photoURL = "";
    isLoggedIn = false;
    emailValidated = false;
  }
}
class SettingsProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isVoicePromptOn = false;
  int _logPointPerMeter = 0;
  bool _isLoading = false;

  bool get IsVoicePromptOn => _isVoicePromptOn;
  int get LogPointPerMeter => _logPointPerMeter;
  bool get isLoading => _isLoading;

  Future<void> LoadSettings(String userId) async {
    if (userId == "") return;

    try{
      _isLoading = true;
      notifyListeners();

      DocumentSnapshot doc = await _firestore
          .collection(CollectionUsers)
          .doc(userId)
          .collection(CollectionSettings)
          .doc(DocAppSettings)
          .get();

      // Create Default Settings
      if (!doc.exists) {
        await _firestore
            .collection(CollectionUsers)
            .doc(userId)
            .collection(CollectionSettings)
            .doc(DocAppSettings)
            .set({
          '$SettingIsVoicePromptOn': true,
          '$SettingLogPointPerMeter': 10,
        });

        _isVoicePromptOn = true;
        _logPointPerMeter = 10; // Default value

        printMsg('Default Settings created on Firestore');
      }
      else{
        // Get document data map
        final data = doc.data() as Map<String, dynamic>?;

        // Safely access data with proper typing
        _isVoicePromptOn = data?[SettingIsVoicePromptOn] as bool? ?? true;

        // For numeric values, ensure proper conversion
        if (data?[SettingLogPointPerMeter] != null) {
          // Handle potential type issues - Firestore might store as double
          final pointsValue = data![SettingLogPointPerMeter];
          if (pointsValue is int) {
            _logPointPerMeter = pointsValue;
          } else if (pointsValue is double) {
            _logPointPerMeter = pointsValue.toInt();
          } else if (pointsValue is String) {
            _logPointPerMeter = int.tryParse(pointsValue) ?? 10;
          }
        } else {
          _logPointPerMeter = 10; // Default value
        }
      }
    }
    catch (e){
      print('Error loading settings: $e');
    }
    finally{
      _isLoading = false;
      notifyListeners();
    }
  }
  Future<void> UpdateSetting(String userId, String key, dynamic value) async {

    // Check var type
    if (key == SettingLogPointPerMeter && value is String) {
      try {
        value = int.parse(value);
      } catch (e) {
        print('Error parsing value to int: $e');
        return; // Don't update if value can't be parsed
      }
    }
    await _firestore
        .collection(CollectionUsers)
        .doc(userId)
        .collection(CollectionSettings)
        .doc(DocAppSettings)
        .set(
      {key: value},
      SetOptions(
          merge: true
      ), // Ensures we update only specified settings
    );

    if (key == SettingIsVoicePromptOn) _isVoicePromptOn = value;
    if (key == SettingLogPointPerMeter) _logPointPerMeter = value as int;

    notifyListeners();
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
            color: Colors.white
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