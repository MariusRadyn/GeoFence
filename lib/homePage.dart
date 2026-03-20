import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/IotDataPage.dart';
import 'package:geofence/operatorsPage.dart';
import 'package:geofence/TrackingPage.dart';
import 'package:geofence/baseStationPage.dart';
import 'package:geofence/geofencePage.dart';
import 'package:geofence/profilePage.dart';
import 'package:geofence/settingsPage.dart';
import 'package:geofence/trackingHistoryPage.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'iotMonitorsPage.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin{
  late AnimationController _controller;
  late Animation<double> _animation;
  final double drawerWidth = 250;
  Timer? _loadingTimer;

  final Color colorMenuIcons = Colors.blue;
  final Color colorMenuText = Colors.blueGrey;

  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwController2 = TextEditingController();
  final TextEditingController _userController = TextEditingController();

  @override
  void initState() {
    super.initState();
    mqtt_Service.init();
    _validateUser();
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
  }

  @override
  void dispose() {
    _userController.dispose();
    _emailController.dispose();
    _pwController.dispose();
    _pwController2.dispose();
    _loadingTimer?.cancel();

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
                          backgroundColor: APP_BACKGROUND_COLOR,
                          foregroundColor: Colors.white,
                        ),
                      ),

                      SizedBox(height: 20),

                      // Email
                      Padding(
                        padding: EdgeInsets.only(left: 20, right: 20),
                        child: MyTextFormField(
                          controller: _emailController,
                          hintText: "Enter Email Address",
                          backgroundColor: APP_BACKGROUND_COLOR,
                          foregroundColor: Colors.white,
                        ),
                      ),

                      SizedBox(height: 20),

                      // Password 1
                      Padding(
                        padding: EdgeInsets.only(left: 20, right: 20),
                        child: MyTextFormField(
                          controller: _pwController,
                          hintText: "Password",
                          backgroundColor: APP_BACKGROUND_COLOR,
                          foregroundColor: Colors.white,
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
                          backgroundColor: APP_BACKGROUND_COLOR,
                          foregroundColor: Colors.white,
                          isPasswordField: true,
                        ),
                      ),

                      SizedBox(height: 30),

                      // Buttons Cancel / OK
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
                            onPressed: () async {
                              final user = await signUp(context);

                              if (user != null) {
                                Navigator.of(context).pop(); // close current dialog FIRST
                                await _sendValidateEmail();
                                _showEmailVerificationDialog(context);
                              }
                            },
                            style: MyButtonStyle(COLOR_ORANGE),
                            child: const Text(
                              "OK",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal
                              ),
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
  Future<User?> signUp(BuildContext context) async {
    UserDataService userService = context.read<UserDataService>();

    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      myMessageBox(context, 'Please enter both email and password.');
      return null;
    }
    if (!_emailController.text.contains('@')) {
      myMessageBox(context, 'Please enter a valid email address.');
      return null;
    }
    if (_userController.text.isEmpty) {
      myMessageBox(context,'Please enter Username.');
      return null;
    }
    if (_pwController.text != _pwController2.text) {
      myMessageBox(context, 'Passwords don''t match.');
      return null;
    }

    try {
      User? user = await firebaseAuthService.fireAuthCreateUserWithEmail(
          context,
          _emailController.text,
          _pwController.text
      );

      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection(CollectionUsers)
            .doc(user.uid)
            .get();

        // Create user ONLY if it does not exist
        if (!doc.exists) {
          userService.create(
              UserData(
                displayName: _userController.text ?? "",
                email: _emailController.text ?? "",
                emailValidated: user.emailVerified ?? false,
              ),
              uid: user.uid
          );

          print('User Created');
        }

        return user;

      } else {
        userService.logout();
      }
    } catch (e) {
      print('Error: $e');
    }
    return null;
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
  Future<bool> loginWithEmail(BuildContext context) async {
    UserDataService userService = context.read<UserDataService>();

    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      myMessageBox(context, 'Please enter both email and password.');
      return false;
    }
    if (!_emailController.text.contains('@')) {
      myMessageBox(context, 'Please enter a valid email address.');
      return false;
    }

    try {
      User? user = await firebaseAuthService.fireAuthSignInWithEmail(
        context,
        _emailController.text,
        _pwController.text,
      );

      // Logged In
      if (user != null) {
        // userService.create(
        //     UserData(
        //       displayName: user.displayName ?? "",
        //       email: _emailController.text,
        //       emailValidated: user.emailVerified ?? false,
        //       isLoggedIn: true,
        //       photoURL: user.photoURL ?? ""
        //     ),
        //   uid: user.uid
        // );

        if(userService.userdata != null){
          userService.isLoggedIn = true;
        }
        printMsg('User logged in');

      } else {
        // Logged ERROR
        if(userService.userdata != null){
          userService.isLoggedIn = false;
        }
        GlobalMsg.show("Login Error: ", userService.userdata!.errorMsg);
      }
    } catch (e) {
      printMsg('Error: $e');
      return false;
    }
    return true;
  }
  Future<bool> loginWithGoogle(BuildContext context) async {
    UserDataService userService = context.read<UserDataService>();

    try {
      UserCredential? userCred = await firebaseAuthService.signInWithGoogle();

      final doc = await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(userCred.user!.uid)
          .get();

      // Create user ONLY if it does not exist
      if (!doc.exists) {
        if (userCred.user != null && userCred.user!.emailVerified) {
          userService.create(
              UserData(
                displayName:  userCred.user?.displayName ?? "",
                email: userCred.user?.email ?? "",
                emailValidated: true,
                photoURL: userCred.user?.photoURL ?? "",
                //isLoggedIn: true,
              ),
              uid: userCred.user!.uid
          );

          printMsg('User logged in with Google');

        } else {
          if(!userCred.user!.emailVerified){
            GlobalMsg.show("Error", "Email address not verified");
            return false;
          }
          else {
            GlobalMsg.show("Error", "Firebase User Credential == Null");
            return false;
          }
        }
      }
    } catch (e) {
      printMsg('Sign in With Google Error: $e');
      myMessageBox(context, 'Google Sign in Error: $e');
      return false;
    }

    return true;
  }
  Future<bool> resetPasswordWithEmail(BuildContext context) async {
    UserDataService userService = context.read<UserDataService>();

    if (_emailController.text.isEmpty) {
      myMessageBox(context, 'Please enter email address.');
      return false;
    }
    if (!_emailController.text.contains('@')) {
      myMessageBox(context, 'Please enter a valid email address.');
      return false;
    }

    try {
      if(await firebaseAuthService.fireAuthResetPassword(context, _emailController.text)) {
        if(userService.userdata != null){
          userService.isLoggedIn = false;
        }
        printMsg('Password Reset');
        return true;
      }
      else return false;

    } catch (e) {
      printMsg('Reset Password: $e');
      return false;
    }
  }

  Future<void> showLoginScreen (BuildContext context) async{
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return
          Dialog(
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
                child: SafeArea(
                  child: SingleChildScrollView(
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
                            backgroundColor: APP_BACKGROUND_COLOR,
                            foregroundColor: Colors.white,
                            controller: _emailController,
                            hintText: "Email Address",
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Password
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: MyTextFormField(
                            foregroundColor: Colors.white,
                            backgroundColor: APP_BACKGROUND_COLOR,
                            controller: _pwController,
                            hintText: "Password",
                            isPasswordField: true,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Reset Password
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const MyText(
                              text: "Forgot Password?",
                              color: Colors.grey,
                              fontsize: 14,
                            ),

                            const SizedBox(width: 10),

                            GestureDetector(
                              onTap: () async {
                                if(await resetPasswordWithEmail(context)){
                                  MyAlertDialog(context, "Password Reset", "Please check your email and follow the instructions");
                                }
                                //Navigator.of(context).pop();
                              },
                              child: const Text(
                                "Reset",
                                style: TextStyle(color: COLOR_ORANGE),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Buttons Cancel / OK
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
                              onPressed: () async {
                                await loginWithEmail(context);
                                Navigator.of(context).pop();
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

                        // Google / Facebook
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [

                            // Sign In with Google
                            _buildSocialLoginButton(
                              context: context,
                              onPressed: () async {
                                await loginWithGoogle(context);
                                Navigator.of(context).pop();
                              },
                              iconPath: ICON_GOOGLE,
                            ),

                            const SizedBox(width: 20),

                            // Sign In with facebook
                            _buildSocialLoginButton(
                              context: context,
                              onPressed: () {
                                // loginWithFacebook implementation would go here
                                Navigator.of(context).pop();
                              },
                              iconPath: ICON_FACEBOOK,
                            ),
                          ],
                        ),

                        SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
      },
    );
  }
  Future<void> _validateUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      await user.reload();   // 🔥 Forces server check
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        await FirebaseAuth.instance.signOut();
      }
    }
  }
  Future<void> _sendValidateEmail() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      await user.sendEmailVerification();   // 🔥 Forces server check
    } catch (e) {
      MyAlertDialog(context, "Verify Email Error", e.toString());
    }
  }
  void _showEmailVerificationDialog(BuildContext context) {
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,

      builder: (context) {
        timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
          final user = FirebaseAuth.instance.currentUser;

          if (user == null) {
            timer.cancel();
            Navigator.of(context).pop();
            return;
          }

          await user.reload(); // 🔥 Force server refresh

          if (user.emailVerified) {
            timer.cancel();
            Navigator.of(context).pop(); // Close dialog
          }
        });

        return AlertDialog(
          title: const Text("Email Verification"),
          content: const Text(
            "Please click the verification link sent to your email.\n\n"
                "This window will close automatically once verified.",
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(
              color: Colors.blue, // Border color
              width: 2, // Border width
            ),
          ),
          backgroundColor: APP_TILE_COLOR,
          shadowColor: Colors.black,
          actions: [
            TextButton(
              onPressed: () async {
                await _sendValidateEmail();
              },
              child: const MyText(text:  "Resend Email"),
            ),
            TextButton(
              onPressed: () async {
                timer?.cancel();
                await FirebaseAuth.instance.signOut();
                Navigator.of(context).pop();
              },
              child: const MyText(text: "Cancel"),
            ),
          ],
        );
      },
    );
  }
  void _startLoadingTimeout() {
    _loadingTimer?.cancel();

    _loadingTimer = Timer(const Duration(seconds: 15), () async {
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
      }
    });
  }
  void _cancelLoadingTimeout() {
    _loadingTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {

    return
      StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          
          return Consumer2<SettingsService, UserDataService>(
              builder: (context, settings, user,__){

                final isLoading = settings.isLoading || user.isLoading || snapshot.connectionState == ConnectionState.waiting;
                final userLoggedIn = snapshot.hasData && user.userdata != null;

                ImageProvider profileImage;

                if (!isLoading &&
                    userLoggedIn &&
                    user.userdata?.photoURL.isNotEmpty == true) {
                  profileImage = NetworkImage(user.userdata!.photoURL);
                } else {
                  profileImage = AssetImage(IMAGE_PROFILE);
                }

                if (isLoading) {
                  _startLoadingTimeout();
                } else {
                  _cancelLoadingTimeout();
                }

                return Scaffold(
                  appBar: AppBar(
                    iconTheme: IconThemeData(color: COLOR_ICE_BLUE),
                    backgroundColor: APP_BAR_COLOR,
                    leading: GestureDetector(
                      onTap: (){
                        if(userLoggedIn) toggleDrawer();
                      },
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
                        ),

                        Text(
                          settings.isBaseStationConnected != true
                              ? "No Connection"
                              : settings.fireSettings == null
                              ? "Loading ..."
                              : settings.fireSettings!.connectedDevice,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
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
                              onTap: () async {
                                if (!isLoading && userLoggedIn) {
                                  if (user.userdata?.emailValidated != true) {
                                    MyAlertDialog(
                                      context,
                                      "Verify Email",
                                      "Please open your email.\nClick on verify link",
                                    );
                                    return;
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => profilePage(
                                      ),
                                    ),
                                  );
                                  //showLogoutDialog(context);
                                }

                                if (!isLoading && !userLoggedIn) {
                                 await showLoginScreen(context);
                                 await user.load();
                                };
                              },

                              // Profile Pic
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.white,
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundImage: profileImage,
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
                              if (!isLoading && userLoggedIn){
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => SettingsPage(
                                        userId: user.userdata!.userID
                                    ),
                                  ),
                                );
                              }
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
                      : !userLoggedIn
                        ? Center(child: MyText(text: "Please  Log in"),)
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
                                imagePath: ICON_TRACK,
                                header: 'Track',
                                description: 'Track your vehicle as it moves inside and outside of your GeoFences',
                                widget: TrackingPage(),
                              ),

                              const SizedBox(height: 10),

                              // GeoFence
                              const MyCustomTileWithPic(
                                imagePath: ICON_GEOFENCE,
                                header: 'GeoFence',
                                description: 'Set all the fence perimeters where you would like to record refundable tax rebate',
                                widget: GeoFencePage(),
                              ),

                              const SizedBox(height: 10),

                              // Base Stations
                              MyCustomTileWithPic(
                                imagePath: ICON_BASE,
                                header: 'Base Stations',
                                description: 'Add multiple base stations that acts as master network controllers.',
                                widget: BaseStationPage(),
                              ),

                              const SizedBox(height: 10),

                              // iOT Monitors
                              const MyCustomTileWithPic(
                                imagePath: ICON_IOT,
                                header: 'iOT Monitors',
                                description: 'Add multiple iOT monitors for various use cases',
                                widget: IotMonitorsPage(),
                              ),

                              const SizedBox(height: 10),

                              const MyCustomTileWithPic(
                                imagePath: ICON_REPORT,
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
                                                      ICON_LIMITLESS_LOGO,
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
                                                          text: user.userdata!.displayName ?? "Not Logged in",
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
                                                          builder: (context) => BaseStationPage()),
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
                                                      Icons.dataset,
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

                                                // Operator Data
                                                ListTile(
                                                  leading: Icon(
                                                      Icons.person,
                                                      color: colorMenuIcons
                                                  ),
                                                  title: Text("Operators",
                                                    style: TextStyle(color: colorMenuText),
                                                  ),
                                                  onTap: () {
                                                    toggleDrawer();
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (context) => OperatorsPage()),
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
                                                          builder: (context) => SettingsPage(
                                                              userId: user.userdata!.userID)
                                                      ),
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
                      ]
                  ),
                );
              }
          );    // Not logged in
        },
      );


  }
}
