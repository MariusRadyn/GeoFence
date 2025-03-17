import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

import 'package:geofence/firebase.dart';
import 'package:geofence/homePage.dart';

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
const COLOR_DARK_HEADER = Colors.white;
const COLOR_DARK_TEXT = Colors.white;
const COLOR_BLACK = Color(0xFF14140F);
const COLOR_BLACK_LIGHT = Color(0x10A3CCAB);
const COLOR_TEAL_LIGHT = Color(0xFFA3CCAB);
const COLOR_TEAL_MID = Color(0xFF34675C);
const COLOR_TEAL_DARK = Color(0xFF053D38);
const COLOR_ORANGE = Color.fromARGB(255, 255, 60, 1);
const COLOR_GREY = Color.fromARGB(139, 119, 119, 119);

UserData userData = UserData();
final FirebaseAuthService firebaseAuthService = FirebaseAuthService();
final FirebaseFirestore firestore = FirebaseFirestore.instance;
//final FirebaseAuth _auth = FirebaseAuth.instance;

final String fireUserName = 'user1';
final String fireUserRecyclebin = '${fireUserName}_recycle/';
const String DB_TABLE_USERS = 'UserTable';

final String iconWARNING = "assets/warning.png";
final String iconGOOGLE = 'assets/google_icon.png';
final String iconFACEBOOK = 'assets/facebook_icon.png';
final String picPROFILE = 'assets/profile.png';


//---------------------------------------------------
// Methods
//---------------------------------------------------
void printMsg(String msg) {
  if (isDebug) print(msg);
}

void writeLog(var text) {
  debugLog += text +'\r';
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

class MyMessageBox {
  final String message;
  final String header;
  String image;

  MyMessageBox({required this.message, required this.header, this.image = ""});

  Future<void> dialogBuilder(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: SizedBox(
            width: 250, // Custom width
            height: 200, // Custom height

            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Heading
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Image
                        Image.asset(image, height: 30, width: 30),
                        SizedBox(width: 8),
                        // Heading
                        Text(
                          header,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ]),
                  SizedBox(height: 10),
                  // Message
                  Text(
                    message,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),
                  // Button
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close the dialog
                    },
                    //style: MyButtonStyle(COLOR_ORANGE), // Button color
                    child: const Text(
                      "OK",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ]),
          ),
        );
      },
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

//---------------------------------------------------
// Widgets
//---------------------------------------------------
class myCustomTileWithPic extends StatelessWidget {
  final String imagePath;
  final String text;
  final Widget widget;

  const myCustomTileWithPic({
    required this.imagePath,
    required this.text,
    required this.widget,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children:[
              GestureDetector(
                onTap: (){
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => widget),
                  );
                },
                child: Container(
                  padding: EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [
                        0.1,
                        0.9
                      ],
                      colors: [
                        COLOR_ICE_BLUE,
                        COLOR_BLUE,
                      ],
                    ),
                    borderRadius: BorderRadius.only(bottomLeft:  Radius.circular(10), bottomRight: Radius.circular(10),),
                  ),
                  child: Column(
                    children: [
                      Image.asset (imagePath, width: 100, height: 100, fit: BoxFit.cover),
                      const SizedBox(height: 8.0),
                      Text(
                        text,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LoginHeader extends StatefulWidget {
  const
  LoginHeader({super.key});

  @override
  State<LoginHeader> createState() => _LoginHeaderState();
}
class _LoginHeaderState extends State<LoginHeader> {

  void login(){
    MyLoginBox().dialogBuilder(context);

    setState(() {
      userData = userData;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          // Backdrop
          Container(
            alignment: Alignment.topCenter,
            height: 200,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: [
                    0.3,
                    0.9,
                  ],
                  colors: [
                    COLOR_BLUE,
                    COLOR_ICE_BLUE,
                  ]),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(100),
                bottomRight: Radius.circular(100),
              ),
            ),
          ),
          // White Container
          Container(
            margin:
            const EdgeInsets.only(top: 60, left: 10, right: 10),
            height: 150,
            decoration: const BoxDecoration(
              color: Colors.white70,
              borderRadius: BorderRadius.all(
                Radius.circular(20),
              ),
            ),
          ),
          // Avatar
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      //     Navigator.push(
                      //       context,
                      //       MaterialPageRoute(
                      //           builder: (context) => HomePage()),
                      //     );
                    },
                    child:CircleAvatar(
                      radius: 55,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        backgroundImage:
                        userData.photoURL?.isEmpty ?? true
                            ? AssetImage(picPROFILE)
                            : NetworkImage(userData.photoURL)
                        as ImageProvider,
                        radius: 50,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Welcome Message
          Center(
            child: Container(
              padding: EdgeInsets.only(top: 130),
              child: showWelcomeMsg(),
            ),
          ),
          // Login Button
          Center(
            child: Container(
              margin: EdgeInsets.only(top: 180),
              width: 120,
              height: 40,
              decoration: const BoxDecoration(
                  color: COLOR_ORANGE,
                  borderRadius:
                  BorderRadius.all(Radius.circular(20))),
              child: TextButton(
                child: userData.isLoggedIn
                    ? const Text(
                  'Log Out',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                )
                    : const Text(
                  'Log In',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                onPressed: () {
                  userData.isLoggedIn == true
                      ? MyMessageBox(
                      message: "You are logged in",
                      header: "Logged In").dialogBuilder(context)
                      : login();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget showWelcomeMsg() {
  if (userData.isLoggedIn) {
    return Text(
      'Welcome ${userData.displayName}',
      style: TextStyle(
        color: Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  } else {
    return Text(
      'Please login to continue',
      style: TextStyle(
        color: Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.bold,
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

  Future<void> dialogBuilder(BuildContext context) {
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
                    Text(
                      "Login",
                      textAlign: TextAlign.center,
                      style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),

                    SizedBox(height: 10),

                    // Email
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: textInputWidget(
                        controller: _emailController,
                        hintText: "Email Address",
                      ),
                    ),

                    SizedBox(height: 20),

                    // Password
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: textInputWidget(
                        controller: _pwController,
                        hintText: "Password",
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

                    SizedBox(height: 20),

                    // Register
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text("Dont have an account?"),
                      SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          MySignupBox().dialogBuilder(context);
                        },
                        child: Text(
                          "Register",
                          style: TextStyle(color: COLOR_ORANGE),
                        ),
                      ),
                    ]),

                    SizedBox(height: 20),

                    // Signin with Google
                    Container(
                      margin: MediaQuery.of(context).size.width > 600
                          ? const EdgeInsets.only(left: 110, right: 110)
                          : const EdgeInsets.only(left: 30, right: 30),
                      child: TextButton(
                        onPressed: () {
                          loginWithGoogle(context);
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
                          loginWithGoogle(context);
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
    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      MyMessageBox(
        header: "Login Error",
        message: 'Please enter both email and password.',
        image: iconWARNING,
      ).dialogBuilder(context);
      return;
    }

    if (!_emailController.text.contains('@')) {
      MyMessageBox(
        header: "Login Error",
        message: 'Please enter a valid email address.',
        image: iconWARNING,
      ).dialogBuilder(context);
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
          _emailController.text, _pwController.text);

      // Pop status indicator
      Navigator.of(context).pop();

      if (user != null) {
        firebaseAuthService.updateDisplayName("Marius");
        userData.login(user);

        printMsg('User logged in');
        Navigator.of(context).pop();
      } else {
        userData.logout();
        printMsg(userData.errorMsg);
        MyMessageBox(
            header: "Error", message: userData.errorMsg, image: iconWARNING)
            .dialogBuilder(context);
      }
    } catch (e) {
      // Pop status indicator
      Navigator.of(context).pop();
      printMsg('Error: $e');
    }
  }

  void loginWithGoogle(BuildContext context) async {
    bool showError = false;

    try {
      userData.Clear();
      UserCredential? userCred = await firebaseAuthService.signInWithGoogle();

      if (userCred.user?.emailVerified != null) {
        userData.login(userCred.user!);

        //bool usrExists = await fireDbcheckIfUserExists(userCred.user!.uid);
        //if (usrExists == false) {
        //  fireDbCreateUser(userCred.user!);
        //}

        printMsg('User logged in with Google');
      } else {
        userData.logout();
        printMsg(userData.errorMsg);

        MyMessageBox(
            header: "Error", message: userData.errorMsg, image: iconWARNING)
            .dialogBuilder(context);
      }
    } catch (e) {
      printMsg('Sign in With Google Error: $e');
      showError = true;
      userData.errorMsg = e.toString();
    } finally {
      Navigator.of(context).pop();

      if (showError) {
        MyMessageBox(
            header: "Error", message: userData.errorMsg, image: iconWARNING)
            .dialogBuilder(context);
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
                      child: textInputWidget(
                        controller: _userController,
                        hintText: "Enter Username",
                      ),
                    ),

                    SizedBox(height: 20),

                    // Email
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: textInputWidget(
                        controller: _emailController,
                        hintText: "Enter Email Address",
                      ),
                    ),

                    SizedBox(height: 20),

                    // Password 1
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: textInputWidget(
                        controller: _pwController,
                        hintText: "Password",
                        isPasswordField: true,
                      ),
                    ),

                    SizedBox(height: 20),

                    // Password 2
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: textInputWidget(
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
    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      MyMessageBox(
        header: "Error",
        message: 'Please enter both email and password.',
        image: iconWARNING,
      ).dialogBuilder(context);
      return;
    }

    if (!_emailController.text.contains('@')) {
      MyMessageBox(
        header: "Error",
        message: 'Please enter a valid email address.',
        image: iconWARNING,
      ).dialogBuilder(context);
      return;
    }

    if (_userController.text.isEmpty) {
      MyMessageBox(
        header: "Error",
        message: 'Please enter Username.',
        image: iconWARNING,
      ).dialogBuilder(context);
      return;
    }

    if (_pwController.text != _pwController2.text) {
      MyMessageBox(
        header: "Error",
        message: 'Passwords dont match.',
        image: iconWARNING,
      ).dialogBuilder(context);
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
          _emailController.text, _pwController.text);

      // Pop status indicator
      Navigator.of(context).pop();

      if (user != null) {
        if (user.displayName != null) {
          //user. = _userController.text;
        }
        userData.login(user);

        print('User Created');
        Navigator.of(context).pop();
      } else {
        userData.logout();
        print(userData.errorMsg);
        MyMessageBox(
            header: "Error", message: userData.errorMsg, image: iconWARNING)
            .dialogBuilder(context);
      }
    } catch (e) {
      // Pop status indicator
      Navigator.of(context).pop();
      print('Error: $e');
    }
  }
}

class textInputWidget extends StatefulWidget {
  final TextEditingController? controller;
  final Key? fieldKey;
  final bool? isPasswordField;
  final String? hintText;
  final String? labelText;
  final String? helperText;
  final FormFieldSetter<String>? onSaved;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputType? inputType;
  final double? width;

  const textInputWidget(
      {this.controller,
        this.isPasswordField,
        this.fieldKey,
        this.hintText,
        this.labelText,
        this.helperText,
        this.onSaved,
        this.validator,
        this.width,
        this.onFieldSubmitted,
        this.inputType});

  @override
  _textInputWidgetState createState() => _textInputWidgetState();
}
class _textInputWidgetState extends State<textInputWidget> {
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
        style: TextStyle(fontSize: 14, color: Colors.white),
        controller: widget.controller,
        keyboardType: widget.inputType,
        key: widget.fieldKey,
        obscureText: widget.isPasswordField == true ? _obscureText : false,
        onSaved: widget.onSaved,
        validator: widget.validator,
        onFieldSubmitted: widget.onFieldSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          filled: true,
          hintText: widget.hintText,
          hintStyle: TextStyle(color: Colors.grey),
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

class UserData extends ChangeNotifier {
  String displayName = "";
  String surname = "";
  String userID = "";
  String? email = "";
  String errorMsg = "";
  String photoURL = "";
  bool isLoggedIn = false;
  bool emailValidated = false;

  void login(User user) {
    userID = user.uid;
    email = user.email;
    emailValidated = user.emailVerified;
    displayName = user.displayName ?? "";
    photoURL = user.photoURL ?? "";
    isLoggedIn = true;
    notifyListeners();
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