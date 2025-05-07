import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/GeofencePage.dart';
import 'package:geofence/SettingsPage.dart';
import 'package:geofence/TrackingHistoryPage.dart';
//import 'package:geofence/TrackingPage.dart';
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
  final TextEditingController _pwController2 = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  String userID = "";
  //final _user = FirebaseAuth.instance.currentUser;
  String _userPhotoURL = "";

  @override
  void initState() {
    super.initState();

    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (!mounted) return;
    //
    //   setState(() {
    //     _logPointPerMeterController.text = SettingsService().settings!.logPointPerMeter.toString();
    //   });
    //   //});
    // });

    if(UserDataService().userdata != null) {
      setState(() {
        UserDataService().userdata!.isLoggedIn = true;
        if(UserDataService().userdata!.photoURL != null) _userPhotoURL = UserDataService().userdata!.photoURL;
      });
    }
  }

  @override
  void dispose() {
    _pwController.dispose();
    _emailController.dispose();
    _pwController2.dispose();
    _userController.dispose();
    super.dispose();
  }

  void showSignUpScreen (BuildContext context){
    double _width = MediaQuery.of(context).size.width * 0.8;
    double _height = MediaQuery.of(context).size.height * 0.6;

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
              //shape: RoundedRectangleBorder(
              //  borderRadius: BorderRadius.circular(15),
              //),
              child: SizedBox(
                width: _width > 500 ? 500 : _width, // Custom width
                height: _height > 600 ? 600 : _height, // Custom height

                child: Container(
                  decoration: BoxDecoration(
                      gradient: MyTileGradient(),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.blue,
                          width: 2
                      )
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Heading
                        const MyText(
                          text: "Sign Up",
                          fontsize: 20,
                        ),

                        SizedBox(height: 10),

                        // Username
                        Padding(
                          padding: const EdgeInsets.only(left: 20, right: 20),
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
                ),
              ));
        },
    );
  }
  void signUp(BuildContext context) async {
    //final _userData = Provider.of<UserData>(context, listen: false);
    context.read<UserData>();

    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      myMessageBox(context, 'Please enter both email and password.');
      return;
    }

    if (!_emailController.text.contains('@')) {
      myMessageBox(context, 'Please enter a valid email address.');
      return;
    }

    if (_userController.text.isEmpty) {
      myMessageBox(context,'Please enter Username.');
      return;
    }

    if (_pwController.text != _pwController2.text) {
      myMessageBox(context, 'Passwords don''t match.');
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

        //_userData.update(user);
        UserDataService().update(UserData(
          displayName: user.displayName ?? "",
          email: user.email ?? "",
          emailValidated: user.emailVerified ?? false,
        ));

        print('User Created');
        Navigator.of(context).pop();
      } else {
        UserDataService().logout();
      }
    } catch (e) {
      // Pop status indicator
      Navigator.of(context).pop();
      print('Error: $e');
    }
  }
  void showLoginScreen(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: MyTileGradient(),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.blue,
                  width: 2
                )
              ),

              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
              width: MediaQuery.of(context).size.width * 0.8,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 20),

                  // Heading
                  const MyText(
                    text:  "Login",
                    fontsize: 20,
                  ),

                  const SizedBox(height: 10),

                  // Email
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: MyTextFormField(
                      controller: _emailController,
                      hintText: "Email Address",
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Password
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                        child: const MyText(
                          text:  "Cancel",
                        ),
                      ),

                      const SizedBox(width: 10),

                      // OK Button
                      TextButton(
                        onPressed: () {
                          loginWithEmail(context);
                        },
                        style: MyButtonStyle(COLOR_ORANGE),
                        child: const MyText(
                            text: 'OK',
                          ),
                        ),
                      ],
                  ),

                  const SizedBox(height: 20),

                  // Register
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const MyText(
                        text: "Don't have an account?",
                        color: Colors.grey,
                        fontsize: 14,
                      ),

                      const SizedBox(width: 10),

                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          showSignUpScreen(context);
                        },
                        child: const Text(
                          "Register",
                          style: TextStyle(color: COLOR_ORANGE),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Login with Google
                      _buildSocialLoginButton(
                        context: context,
                        onPressed: () {
                          loginWithGoogle(context);
                          Navigator.of(context).pop();
                        },
                        iconPath: iconGOOGLE,
                      ),

                      const SizedBox(width: 20),

                      // Signin with facebook
                      _buildSocialLoginButton(
                        context: context,
                        onPressed: () {
                          // loginWithFacebook implementation would go here
                        },
                        iconPath: iconFACEBOOK,
                      ),
                    ],
                  ),

                SizedBox(height: 20),

                ],
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _buildSocialLoginButton({
    required BuildContext context,
    required VoidCallback onPressed,
    required String iconPath,
    String text="",
  }) {


    return GestureDetector(
      onTap: onPressed,
      child: CircleAvatar(
        radius: 25,
        backgroundColor: Colors.white,
        child: CircleAvatar(
          radius: 18,
          backgroundImage: AssetImage(iconPath),
        ),
      ),
    );
  }
  void loginWithEmail(BuildContext context) async {
    //final userData = Provider.of<UserData>(context, listen: false);
    UserData? _userData = UserDataService().userdata;

    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      myMessageBox(context, 'Please enter both email and password.');
      return;
    }

    if (!_emailController.text.contains('@')) {
      myMessageBox(context, 'Please enter a valid email address.');
      return;
    }

    // Show status indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      User? user = await firebaseAuthService.fireAuthSignIn(
        context,
        _emailController.text,
        _pwController.text,
      );

      // Pop status indicator
      Navigator.of(context).pop();

      if (user != null) {
        //firebaseAuthService.updateDisplayName("Marius");

        UserDataService().update(UserData(
            //displayName: "Marius",
            displayName: user.displayName ?? "",
            email: _emailController.text,
            emailValidated: user.emailVerified ?? false,
            isLoggedIn: true,
            photoURL: user.photoURL ?? ""
        ));

        printMsg('User logged in');
        Navigator.of(context).pop();
      } else {
        //printMsg(userData.errorMsg);
        //GlobalMsg.show("Error", userData.errorMsg);
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
      UserCredential? userCred = await firebaseAuthService.signInWithGoogle();

      if (userCred != null && userCred.user != null && userCred.user!.emailVerified) {

        UserDataService().update(UserData(
          displayName:  userCred.user?.displayName ?? "",
          email: userCred.user?.email ?? "",
          emailValidated: userCred.user?.emailVerified ?? false,
          photoURL: userCred.user?.photoURL ?? "",
          isLoggedIn: true,
        ));

        printMsg('User logged in with Google');
        UserDataService().printHash();

      } else {
        if(!userCred.user!.emailVerified){
          GlobalMsg.show("Error", "Email address not verified");
        }
        else {
          GlobalMsg.show("Error", "Firebase User Credential == Null");
        }
      }

    } catch (e) {
      printMsg('Sign in With Google Error: $e');
      showError = true;
      UserDataService().userdata?.errorMsg = e.toString();

    } finally {
      if (showError) {
        if(UserDataService().userdata != null) {
          myMessageBox(context, UserDataService().userdata!.errorMsg);
        }
      }
    }
  }
  Widget buildLoginHeader() {
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
                stops: [0.3, 0.9],
                colors: [COLOR_BLUE, COLOR_ICE_BLUE],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(100),
                bottomRight: Radius.circular(100),
              ),
            ),
          ),

          // White Container
          Container(
            margin: const EdgeInsets.only(top: 60, left: 10, right: 10),
            height: 150,
            decoration: const BoxDecoration(
              color: Colors.white70,
              borderRadius: BorderRadius.all(Radius.circular(20)),
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
                      // Navigation logic could go here
                    },
                    child: CircleAvatar(
                      radius: 55,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        backgroundImage: (UserDataService().userdata?.photoURL.isEmpty ?? true)
                            ? AssetImage(picPROFILE)
                            : NetworkImage(UserDataService().userdata!.photoURL) as ImageProvider,
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
              padding: const EdgeInsets.only(top: 130),
              child: ShowWelcomeMsg(context),
            ),
          ),

          // Login Button
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 180),
              width: 120,
              height: 40,
              decoration: const BoxDecoration(
                color: COLOR_ORANGE,
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: TextButton(
                child: Text(
                  UserDataService().userdata!.isLoggedIn ? 'Log Out' : 'Log In',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                onPressed: () {
                  UserDataService().userdata!.isLoggedIn
                      ? myMessageBox(context, "Already logged in")
                      : showLoginScreen(context);
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        title: MyAppbarTitle('GeoFence V1.0'),
        actions: [
          Consumer2<UserDataService, SettingsService>(
            builder: (context, userData, settings, child) {

              if (settings.isLoading && userData.isLoading) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: CircularProgressIndicator(
                        color: Colors.blue,
                        strokeWidth: 2
                    ),
                  ),
                );
              }

              return Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Profile Pic
                    Padding(
                      padding: const EdgeInsets.only(right: 10, top: 2, bottom: 2),
                      child: GestureDetector(
                        onTap: () {
                          if (userData.userdata!.isLoggedIn) {
                            GlobalMsg.show("Login","Already logged in");
                          } else {
                            showLoginScreen(context);
                          }
                        },

                        // Profile Pic
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundImage: userData.userdata!.isLoggedIn
                                ? NetworkImage(userData.userdata!.photoURL) as ImageProvider
                                : AssetImage(picPROFILE),
                          ),
                        ),
                      ),
                    ),

                    // Settings
                    IconButton(
                      icon: const Icon(
                        Icons.settings,
                        size: 40,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SettingsPage(userId: UserDataService().userdata!.userID),
                          ),
                        );
                      },
                    ),
                  ],
              );
            },
          ),
        ],
      ),
      backgroundColor: COLOR_DARK_BLUE,
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 50),

            // Tiles
            myCustomTileWithPic(
              imagePath: 'assets/track.jpg',
              header: 'Track',
              description: 'Track your vehicle as it moves inside and outside of your GeoFences',
              widget:GeoFencePage(),// TrackingPage(userId: userID),
            ),

            const SizedBox(height: 10),

            const myCustomTileWithPic(
              imagePath: 'assets/geofence.jpg',
              header: 'GeoFence',
              description: 'Set all the fence perimeters where you would like to record refundable tax rebate',
              widget: GeoFencePage(),
            ),

            const SizedBox(height: 10),

            const myCustomTileWithPic(
              imagePath: 'assets/red_pickup2.png',
              header: 'Vehicles',
              description: 'Add all the vehicles in your fleet',
              widget: VehiclesPage(),
            ),

            const SizedBox(height: 10),

            const myCustomTileWithPic(
              imagePath: 'assets/report.png',
              header: 'Tracking History',
              description: 'View tracking history',
              widget: TrackingHistoryPage(),
            ),
          ],
        ),
      ),
    );
  }
}
