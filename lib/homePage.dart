import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/GeofencePage.dart';
import 'package:geofence/SettingsPage.dart';
import 'package:geofence/TrackingPage.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';

import 'VehiclesPage.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void Dispose() {
    _pwController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> LoginScreen(BuildContext context, UserData _userData) {
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
                      child: MyTextFormField(
                        controller: _emailController,
                        hintText: "Email Address",
                      ),
                    ),

                    SizedBox(height: 20),

                    // Password
                    Padding(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: MyTextFormField(
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

                    // Login with Google
                    Container(
                      margin: MediaQuery.of(context).size.width > 600
                          ? const EdgeInsets.only(left: 110, right: 110)
                          : const EdgeInsets.only(left: 30, right: 30),
                      child: TextButton(
                        onPressed: () {
                          loginWithGoogle(context, _userData);
                          Navigator.of(context).pop();
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
                          //Navigator.of(context).pop();
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
      MyMessageBox(context, 'Please enter both email and password.');
      return;
    }

    if (!_emailController.text.contains('@')) {
      MyMessageBox(context,'Please enter a valid email address.');
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
      if (showError) {
        MyMessageBox(context, _userData.errorMsg);
      }
    }
  }
  Widget LoginHeader(UserData _userData){
    return SafeArea(
        child:Stack(
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
                          _userData.photoURL?.isEmpty ?? true
                              ? AssetImage(picPROFILE)
                              : NetworkImage(_userData.photoURL)
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
                child: ShowWelcomeMsg(context),
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
                  child: _userData.isLoggedIn
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
                    _userData.isLoggedIn == true
                        ? MyMessageBox(context, "Already logged in")
                        : LoginScreen(context, _userData);
                  },
                ),
              ),
            ),
          ],
        ),
    );
}

@override
  Widget build(BuildContext context) {
    //final _isLoggedIn = context.select((UserData u) => u.isLoggedIn);

  final userData = Provider.of<UserData>(context, listen: false);
  //final _settings = Provider.of<SettingsProvider>(context, listen: true);

  return Scaffold(
        appBar: AppBar(
          backgroundColor: APP_BAR_COLOR,
          title: MyAppbarTitle('GeoFence'),
          actions: [
            Consumer2<UserData, SettingsProvider>(
              builder: (context, _userData, _settings, child) {
                return Row(
                  children:[
                    Padding(
                      padding: const EdgeInsets.only(right: 10,top: 2,bottom: 2),
                      child: GestureDetector(
                        onTap: () =>{
                          _userData.isLoggedIn == true
                              ? MyMessageBox(context, "Already logged in")
                              : LoginScreen(context, _userData),

                          if(_userData.isLoggedIn) _settings.LoadSettings(_userData.userID),
                        },
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundImage:
                            _userData.photoURL?.isEmpty ?? true
                                ? AssetImage(picPROFILE)
                                : NetworkImage(_userData.photoURL) as ImageProvider,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                        icon:Icon(
                          Icons.settings,
                          size: 40,
                          color: Colors.grey,
                        ),
                        onPressed: ()=>{
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => SettingsPage(userId:  _userData.userID)),
                          ),
                        }
                    )
                  ]
                );
              }
            ),
          ],
        ),
        backgroundColor: COLOR_DARK_BLUE,

      body: SingleChildScrollView(
         child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [

          SizedBox(height: 50),

            // Tiles
            myCustomTileWithPic(
              imagePath: 'assets/track.jpg',
              header: 'Track',
              description: 'Track your vehicle as it moves inside and outside of your GeoFences',
              widget: TrackingPage(
                  userId:  userData.userID
              ),
            ),

            SizedBox(height: 10),

            const myCustomTileWithPic(
              imagePath: 'assets/geofence.jpg',
              header: 'GeoFence',
              description: 'Set all the fence perimeters where you would like to record refundable tax rebate',
              widget: GeoFencePage(),
            ),

            SizedBox(height: 10),

            myCustomTileWithPic(
              imagePath: 'assets/bakkie.jpg',
              header: 'Vehicles',
              description: 'Add all the vehicles in your fleet',
              widget: VehiclesPage(),
            ),

            SizedBox(height: 10),

            myCustomTileWithPic(
              imagePath: 'assets/report.png',
              header: 'Track History',
              description: 'View tracking history',
              widget: GeoFencePage(),
            ),

          ],



          //),
        ),
      )
    );
  }
}
