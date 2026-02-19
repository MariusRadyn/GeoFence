import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/IotDataPage.dart';
import 'package:geofence/TrackingPage.dart';
import 'package:geofence/baseStationPage.dart';
import 'package:geofence/geofencePage.dart';
import 'package:geofence/profilePage.dart';
import 'package:geofence/settingsPage.dart';
import 'package:geofence/trackingHistoryPage.dart';
//import 'package:geofence/TrackingPage.dart';
import 'package:geofence/utils.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'iotMonitorsPage.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin{
  late SettingsService settings;

  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwController2 = TextEditingController();
  final TextEditingController _userController = TextEditingController();

  late AnimationController _controller;
  late Animation<double> _animation;
  final double drawerWidth = 250;

  final Color colorMenuIcons = Colors.blue;
  final Color colorMenuText = Colors.blueGrey;

  @override
  void initState() {
    super.initState();

    mqtt_Service.init();

    if(UserDataService().userdata != null) {
      setState(() {
        UserDataService().userdata!.isLoggedIn = true;
      });
    }

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation = Tween<double>(
      begin: -drawerWidth,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.watch<SettingsService>();
  }

  @override
  void dispose() {
    _pwController.dispose();
    _emailController.dispose();
    _pwController2.dispose();
    _userController.dispose();
    super.dispose();
  }

  void toggleDrawer() {
    if (_controller.isCompleted) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }
  void showSignUpScreen (BuildContext context){
    double width = MediaQuery.of(context).size.width * 0.8;
    double height = MediaQuery.of(context).size.height * 0.6;

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
              //shape: RoundedRectangleBorder(
              //  borderRadius: BorderRadius.circular(15),
              //),
              child: SizedBox(
                width: width > 500 ? 500 : width, // Custom width
                height: height > 600 ? 600 : height, // Custom height

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
        UserDataService().create(UserData(
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
    UserData? userData = UserDataService().userdata;

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

        UserDataService().create(UserData(
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

      if (userCred.user != null && userCred.user!.emailVerified) {

        UserDataService().create(UserData(
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

  @override
  Widget build(BuildContext context) {
    final userDataService = context.watch<UserDataService>();

    final isLoading =
        userDataService.userdata == null ||
            (settings.isLoading && userDataService.isLoading);


    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: COLOR_ICE_BLUE),
        backgroundColor: APP_BAR_COLOR,
        leading: GestureDetector(
          onTap: toggleDrawer,
          child: Icon(Icons.menu),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LimitLess iOT',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.normal,
                fontFamily: 'Poppins',
                color: Colors.white,
              ),
            ), Consumer<SettingsService>(
              builder: (_, _settings, __) {
                return
                Text(
                  _settings.isBaseStationConnected != true
                      ? "No Connection"
                      : _settings.fireSettings == null
                      ? "Loading ..."
                      : _settings.fireSettings!.connectedDevice,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                // Profile Pic
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2, bottom: 2),
                  child: GestureDetector(
                    onTap: () {
                      if (isLoading){
                         Navigator.push(
                             context,
                             MaterialPageRoute(
                             builder: (context) => profilePage(),
                          ),
                         );
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
                        backgroundImage: isLoading == false
                            ? NetworkImage(userDataService.userdata!.photoURL) as ImageProvider
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
          ),
        ],
      ),
      backgroundColor: APP_BACKGROUND_COLOR,
      body: isLoading
        ? Scaffold(
            backgroundColor: APP_BACKGROUND_COLOR,
            body: MyProgressCircle(),
         )
      : Stack(
        children:[
          // =========================
          // Page Data
          // =========================
          SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 50),

                // Track Vehicle
                MyCustomTileWithPic(
                  imagePath: 'assets/track.jpg',
                  header: 'Track',
                  description: 'Track your vehicle as it moves inside and outside of your GeoFences',
                  widget: TrackingPage(),
                ),

                const SizedBox(height: 10),

                // GeoFence
                const MyCustomTileWithPic(
                  imagePath: 'assets/geofence.jpg',
                  header: 'GeoFence',
                  description: 'Set all the fence perimeters where you would like to record refundable tax rebate',
                  widget: GeoFencePage(),
                ),

                const SizedBox(height: 10),

                // Base Stations
                MyCustomTileWithPic(
                  imagePath: 'assets/base_station.png',
                  header: 'Base Stations',
                  description: 'Add multiple base stations that acts as master network controllers.',
                  widget: BaseStationPage(userId: UserDataService().userdata!.userID),
                ),

                const SizedBox(height: 10),

                // iOT Monitors
                const MyCustomTileWithPic(
                  imagePath: 'assets/iot.png',
                  header: 'iOT Monitors',
                  description: 'Add multiple iOT monitors for various use cases',
                  widget: IotMonitorsPage(),
                ),

                const SizedBox(height: 10),

                const MyCustomTileWithPic(
                  imagePath: 'assets/report.png',
                  header: 'Tracking History',
                  description: 'View tracking history',
                  widget: TrackingHistoryPage(),
                ),
              ],
            ),
          ),

          // =========================
          // Menu Drawer
          // =========================
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Positioned(
                left: _animation.value,
                top: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0,5,0,0),
                  child: Container(
                    width: drawerWidth,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.only(
                            topRight: Radius.circular(20),
                            bottomRight: Radius.circular(20)
                        ),
                      color: Colors.white,
                    ),

                    // Menu
                    child: SafeArea(
                      child:  Column(
                          children: [
                            Container(
                              height: 140,
                              width: drawerWidth,
                              decoration: BoxDecoration(
                                gradient: MyTileGradient(),
                                borderRadius: BorderRadius.only(
                                    topRight: Radius.circular(20),
                                ),
                              ),

                              // Menu Header
                              child: Column(
                                children: [
                                  /// TOP ROW
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        "Menu",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                        ),
                                      ),

                                      Image.asset(
                                        'assets/limitless.png',
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.contain,
                                      ),
                                    ],
                                  ),

                                  Spacer(),

                                  /// BOTTOM INFO
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          MyText(
                                            text: APP_VERSION,
                                            color: Colors.grey,
                                          ),
                                          MyText(
                                            text: UserDataService().userdata?.displayName ?? "Not Logged in",
                                            color: Colors.grey,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  SizedBox(height: 10,)
                                ],
                              ),
                            ),

                            // Menu
                            Expanded(
                              child: ListView(
                                padding: EdgeInsets.zero,
                                children: [

                                  // -------------------------
                                  // (HEADING) Tracking
                                  // -------------------------
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: MyTextHeader(
                                      text: "Tracking",
                                      color: Colors.black,
                                      fontsize: 18,
                                      linecolor: APP_BACKGROUND_COLOR,
                                    ),
                                  ),

                                  // Track
                                  ListTile(
                                    leading: Icon(Icons.gps_fixed, color: colorMenuIcons),
                                    title: Text("Track",
                                      style: TextStyle(color: colorMenuText),
                                    ),
                                    onTap: () {
                                      toggleDrawer();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => TrackingPage()),
                                      );
                                    },
                                  ),

                                  // GeoFence
                                  ListTile(
                                    leading: Icon(Icons.fence, color: colorMenuIcons),
                                    title: Text("GeoFence",
                                        style: TextStyle(color: colorMenuText)
                                    ),
                                    onTap: () {
                                      toggleDrawer();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => GeoFencePage()),
                                      );
                                    },
                                  ),

                                  // Tracking History
                                  ListTile(
                                    leading: Icon(
                                        Icons.history,
                                        color: colorMenuIcons
                                    ),
                                    title: Text("Tracking History",
                                        style: TextStyle(color: colorMenuText)
                                    ),
                                    onTap: () {
                                      toggleDrawer();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => TrackingHistoryPage()),
                                      );
                                    },
                                  ),


                                  // -------------------------
                                  // (HEADING) IOT Monitor
                                  // -------------------------
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(10,20,10,0),
                                    child: MyTextHeader(
                                      text: "iOT",
                                      color: Colors.black,
                                      fontsize: 18,
                                      linecolor: APP_BACKGROUND_COLOR,
                                    ),
                                  ),

                                  // Base Station
                                  ListTile(
                                    leading: Icon(
                                        Icons.cell_tower,
                                        color: colorMenuIcons
                                    ),
                                    title: Text("Base Station",
                                        style: TextStyle(color: colorMenuText)
                                    ),
                                    onTap: () {
                                      toggleDrawer();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => BaseStationPage(userId: UserDataService().userdata!.userID)),
                                      );
                                    },
                                  ),

                                  // IOT Monitors
                                  ListTile(
                                    leading: Icon(
                                        Icons.monitor,
                                        color: colorMenuIcons
                                    ),
                                    title: Text("iOT Monitors",
                                      style: TextStyle(color: colorMenuText),
                                    ),
                                    onTap: () {
                                      toggleDrawer();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => IotMonitorsPage()),
                                      );
                                    },
                                  ),

                                  // IOT Data
                                  ListTile(
                                    leading: Icon(
                                        Icons.monitor,
                                        color: colorMenuIcons
                                    ),
                                    title: Text("iOT Data",
                                      style: TextStyle(color: colorMenuText),
                                    ),
                                    onTap: () {
                                      toggleDrawer();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => IotDataPage()),
                                      );
                                    },
                                  ),


                                  // -------------------------
                                  // (HEADING) Settings
                                  // -------------------------
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(10,20,10,0),
                                    child: MyTextHeader(
                                      text: "Settings",
                                      color: Colors.black,
                                      fontsize: 18,
                                      linecolor: APP_BACKGROUND_COLOR,
                                    ),
                                  ),

                                  // Settings
                                  ListTile(
                                    leading: Icon(
                                        Icons.settings,
                                        color: colorMenuIcons
                                    ),
                                    title: Text("Settings",
                                        style: TextStyle(color: colorMenuText)
                                    ),
                                    onTap: () {
                                      toggleDrawer();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => SettingsPage(userId: UserDataService().userdata!.userID)),
                                      );
                                    },
                                  ),

                                SizedBox(height: 5,)
                                ],
                              ),
                            ),
                          ]
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // =========================
          // Side Swipe Handle
          // =========================
          // AnimatedBuilder(
          //   animation: _controller,
          //   builder: (context, child) {
          //     return Positioned(
          //       left: 0,
          //       top: MediaQuery.of(context).size.height / 2 - 30,
          //       child: Opacity(
          //         opacity: 1 - _controller.value,
          //         child: IgnorePointer(
          //           ignoring: _controller.value > 0.9,
          //           child: GestureDetector(
          //             onTap: toggleDrawer,
          //             child: Container(
          //               width: 15,
          //               height: 100,
          //               decoration: BoxDecoration(
          //                 color: Colors.lightBlueAccent,
          //                 borderRadius: const BorderRadius.horizontal(
          //                   right: Radius.circular(25),
          //                 ),
          //                 boxShadow: const [
          //                   BoxShadow(
          //                     color: Colors.black26,
          //                     blurRadius: 6,
          //                   ),
          //                 ],
          //               ),
          //               // child: const Icon(
          //               //   Icons.chevron_right,
          //               //   color: Colors.white,
          //               // ),
          //             ),
          //           ),
          //         ),
          //       ),
          //     );
          //   },
          // ),
        ]
      ),
    );
  }
}
