import 'dart:async';

//import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/iot_data_page.dart';
import 'package:geofence/mqtt_service.dart';
//import 'package:geofence/firebase.dart';
import 'package:geofence/login_page.dart';
import 'package:geofence/operators_page.dart';
import 'package:geofence/Tracking_page.dart';
import 'package:geofence/base_station_page.dart';
import 'package:geofence/geo_fence_page.dart';
import 'package:geofence/profile_page.dart';
import 'package:geofence/settings_page.dart';
import 'package:geofence/tracking_history_page.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'iot_monitors_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with SingleTickerProviderStateMixin{
  final mqttService = MqttService();
  late AnimationController _controllerDraw;
  late Animation<double> _animationDraw;
  final double drawerWidth = 250;
  Timer? _loadingTimer;
  bool busyLoggingIn = false;

  final Color colorMenuIcons = Colors.blue;
  final Color colorMenuHeader = Colors.white;
  final Color colorMenuText = Colors.white;

  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwController2 = TextEditingController();
  final TextEditingController _userController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _validateUser();
    _controllerDraw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animationDraw = Tween<double>(
      begin: -drawerWidth,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _controllerDraw,
        curve: Curves.easeInOut,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
    });
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
    if (_controllerDraw.isCompleted) {
      _controllerDraw.reverse();
    } else {
      _controllerDraw.forward();
    }
  }
  Future<void> _login({
    required bool isLoading,
    required bool userLoggedIn,
    required UserDataService user,
  }) async{
    await user.load();

    if (!isLoading && userLoggedIn) {
      if (user.userdata
          ?.emailValidated != true) {
        MyGlobalMessage.show(
            "Verify Email",
            "Please open your email.\nClick on the verify link",
            MyMessageType.info
        );
        return;
      }

      if(mounted){
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ProfilePage(
                ),
          ),
        );
      }//showLogoutDialog(context);
    }

    if (!isLoading && !userLoggedIn) {
      if(mounted){
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LoginPage(),
          ),
        );
      }

      //await _loginScreen();
      await user.load();
    }
  }

  // void _signUpScreen (){
  //   double width = MediaQuery.of(context).size.width * 0.8;
  //   double height = MediaQuery.of(context).size.height * 0.6;
  //
  //   _emailController.text = "";
  //   _pwController.text = "";
  //   _pwController2.text = "";
  //   _userController.text = "";
  //
  //   showDialog<void>(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return Dialog(
  //           backgroundColor: Colors.transparent,
  //           //shape: RoundedRectangleBorder(
  //           //  borderRadius: BorderRadius.circular(15),
  //           //),
  //           child: SizedBox(
  //             width: width > 500 ? 500 : width, // Custom width
  //             height: height > 600 ? 600 : height, // Custom height
  //
  //             child: Container(
  //               decoration: BoxDecoration(
  //                   gradient: MyTileGradient(),
  //                   borderRadius: BorderRadius.circular(10),
  //                   border: Border.all(
  //                       color: Colors.blue,
  //                       width: 2
  //                   )
  //               ),
  //               child: Column(
  //                   mainAxisAlignment: MainAxisAlignment.center,
  //                   mainAxisSize: MainAxisSize.min,
  //                   children: [
  //
  //                     // Heading
  //                     const MyText(
  //                       text: "Sign Up",
  //                       fontsize: 20,
  //                     ),
  //
  //                     SizedBox(height: 10),
  //
  //                     // Username
  //                     Padding(
  //                       padding: const EdgeInsets.only(left: 20, right: 20),
  //                       child: MyTextFormField(
  //                         controller: _userController,
  //                         hintText: "Enter Username",
  //                         backgroundColor: colorAppBackground,
  //                         foregroundColor: Colors.white,
  //                       ),
  //                     ),
  //
  //                     SizedBox(height: 20),
  //
  //                     // Email
  //                     Padding(
  //                       padding: EdgeInsets.only(left: 20, right: 20),
  //                       child: MyTextFormField(
  //                         controller: _emailController,
  //                         hintText: "Enter Email Address",
  //                         backgroundColor: colorAppBackground,
  //                         foregroundColor: Colors.white,
  //                       ),
  //                     ),
  //
  //                     SizedBox(height: 20),
  //
  //                     // Password 1
  //                     Padding(
  //                       padding: EdgeInsets.only(left: 20, right: 20),
  //                       child: MyTextFormField(
  //                         controller: _pwController,
  //                         hintText: "Password",
  //                         backgroundColor: colorAppBackground,
  //                         foregroundColor: Colors.white,
  //                         isPasswordField: true,
  //                       ),
  //                     ),
  //
  //                     SizedBox(height: 20),
  //
  //                     // Password 2
  //                     Padding(
  //                       padding: EdgeInsets.only(left: 20, right: 20),
  //                       child: MyTextFormField(
  //                         controller: _pwController2,
  //                         hintText: "Confirm Password",
  //                         backgroundColor: colorAppBackground,
  //                         foregroundColor: Colors.white,
  //                         isPasswordField: true,
  //                       ),
  //                     ),
  //
  //                     SizedBox(height: 30),
  //
  //                     // Buttons Cancel / OK
  //                     Row(
  //                       mainAxisAlignment: MainAxisAlignment.center,
  //                       children: [
  //
  //                         // Cancel Button
  //                         MyTextButton(
  //                           text: 'Cancel',
  //                           onPressed: () {
  //                             Navigator.of(context).pop();
  //                           },
  //                         ),
  //
  //                         SizedBox(width: 10),
  //
  //                         // OK Button
  //                         MyTextButton(
  //                           text:'OK',
  //                           onPressed: () async {
  //                             final user = await _signUp();
  //
  //                             if (user != null) {
  //                               if(mounted){
  //                                 Navigator.of(context).pop(); // close current dialog FIRST
  //                                 await _sendValidateEmail();
  //                                 _showEmailVerificationDialog(context);
  //                               }
  //                             }
  //                           },
  //                         ),
  //                       ],
  //                     ),
  //                   ]),
  //             ),
  //           ));
  //     },
  //   );
  // }
  // Future<User?> _signUp() async {
  //   UserDataService userService = context.read<UserDataService>();
  //   AuthResult result = AuthResult();
  //
  //   if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
  //     MyGlobalMessage.show("Info", 'Please enter email and password.', MyMessageType.info);
  //     return null;
  //   }
  //   if (!_emailController.text.contains('@')) {
  //     MyGlobalMessage.show("Info", 'Please enter valid email address.', MyMessageType.info);
  //     return null;
  //   }
  //   if (_userController.text.isEmpty) {
  //     MyGlobalMessage.show("Info", 'Please enter username.', MyMessageType.info);
  //     return null;
  //   }
  //   if (_pwController.text != _pwController2.text) {
  //     MyGlobalMessage.show("Info", 'Passwords dont match.', MyMessageType.info);
  //     return null;
  //   }
  //
  //   try {
  //     result = await firebaseAuthService.fireAuthCreateUserWithEmail(
  //         context,
  //         _emailController.text,
  //         _pwController.text
  //     );
  //
  //     if (result.isSuccess && result.user != null) {
  //       final doc = await FirebaseFirestore.instance
  //           .collection(collectionUsers)
  //           .doc(result.user!.uid)
  //           .get();
  //
  //       // Create user ONLY if it does not exist
  //       if (!doc.exists) {
  //         userService.create(
  //             UserData(
  //               displayName: _userController.text ?? "",
  //               email: _emailController.text ?? "",
  //               emailValidated: result.user!.emailVerified ?? false,
  //             ),
  //             uid: result.user!.uid
  //         );
  //
  //         print('User Created');
  //       }
  //
  //       return result.user;
  //
  //     } else {
  //       if(result.code != null){
  //         MyGlobalMessage.show("Login", result.code!, MyMessageType.warning);
  //       } else {
  //         MyGlobalMessage.show("Login", result.exception.toString(), MyMessageType.warning);
  //       }
  //
  //       userService.logout();
  //     }
  //   } catch (e) {
  //     MyGlobalMessage.show("Error", result.exception.toString(), MyMessageType.error);
  //   }
  //   return null;
  // }
  // Future<bool> _resetPasswordWithEmail() async {
  //   UserDataService userService = context.read<UserDataService>();
  //
  //   if (_emailController.text.isEmpty) {
  //     MyGlobalMessage.show("Info", 'Please enter email address.', MyMessageType.info);
  //     return false;
  //   }
  //   if (!_emailController.text.contains('@')) {
  //     MyGlobalMessage.show("Info", 'Please enter a valid email address.', MyMessageType.info);
  //     return false;
  //   }
  //
  //   try {
  //     if(await firebaseAuthService.fireAuthResetPassword(context, _emailController.text)) {
  //       if(userService.userdata != null){
  //         userService.isUserLoggedIn = false;
  //       }
  //       printMsg('Password Reset');
  //       return true;
  //     }
  //     else {
  //       MyGlobalMessage.show("Error", 'Failed to reset password', MyMessageType.error);
  //       return false;
  //     }
  //
  //   } catch (e) {
  //     MyGlobalMessage.show("Error", '$e', MyMessageType.error);
  //     return false;
  //   }
  // }
  // Future<void> _loginScreen () async{
  //   await showDialog<void>(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return
  //         Dialog(
  //           backgroundColor: Colors.transparent,
  //           child: Padding(
  //             padding: const EdgeInsets.all(8.0),
  //             child: Container(
  //               decoration: BoxDecoration(
  //                   gradient: MyTileGradient(),
  //                   borderRadius: BorderRadius.circular(10),
  //                   border: Border.all(
  //                       color: Colors.blue,
  //                       width: 2
  //                   )
  //               ),
  //
  //               margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
  //               width: MediaQuery.of(context).size.width * 0.8,
  //               child: SafeArea(
  //                 child: SingleChildScrollView(
  //                   child: Column(
  //                     mainAxisAlignment: MainAxisAlignment.center,
  //                     mainAxisSize: MainAxisSize.min,
  //                     children: [
  //                       SizedBox(height: 20),
  //
  //                       // Heading
  //                       const MyText(
  //                         text:  "Login",
  //                         fontsize: 20,
  //                       ),
  //
  //                       const SizedBox(height: 10),
  //
  //                       // Email
  //                       Padding(
  //                         padding: const EdgeInsets.symmetric(horizontal: 20),
  //                         child: MyTextFormField(
  //                           inputType: TextInputType.emailAddress,
  //                           backgroundColor: colorAppBackground,
  //                           foregroundColor: Colors.white,
  //                           controller: _emailController,
  //                           //hintText: "Enter Email Address",
  //                           labelText: "Email",
  //                           valueFontSize: 12,
  //
  //                         ),
  //                       ),
  //                       const SizedBox(height: 20),
  //
  //                       // Password
  //                       Padding(
  //                         padding: const EdgeInsets.symmetric(horizontal: 20),
  //                         child: MyTextFormField(
  //                           foregroundColor: Colors.white,
  //                           backgroundColor: colorAppBackground,
  //                           controller: _pwController,
  //                           //hintText: "Enter Password",
  //                           labelText: "Password",
  //                           isPasswordField: true,
  //                           valueFontSize: 12,
  //                         ),
  //                       ),
  //                       const SizedBox(height: 20),
  //
  //                       // Reset Password
  //                       Row(
  //                         mainAxisAlignment: MainAxisAlignment.center,
  //                         children: [
  //                           const MyText(
  //                             text: "Forgot Password?",
  //                             color: Colors.grey,
  //                             fontsize: 14,
  //                           ),
  //
  //                           const SizedBox(width: 10),
  //
  //                           GestureDetector(
  //                             onTap: () async {
  //                               if(await _resetPasswordWithEmail()){
  //                                 MyGlobalMessage.show("Check email", "Please check your email and follow the instructions", MyMessageType.info);
  //                               }
  //                               //Navigator.of(context).pop();
  //                             },
  //                             child: const Text(
  //                               "Reset",
  //                               style: TextStyle(color: colorOrange),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //
  //                       const SizedBox(height: 10),
  //
  //                       // Sign up
  //                       Row(
  //                         mainAxisAlignment: MainAxisAlignment.center,
  //                         children: [
  //                           const MyText(
  //                             text: "Don't have an account?",
  //                             color: Colors.grey,
  //                             fontsize: 14,
  //                           ),
  //
  //                           const SizedBox(width: 10),
  //
  //                           GestureDetector(
  //                             onTap: () {
  //                               _signUpScreen();
  //                             },
  //                             child: const Text(
  //                               "Sign up",
  //                               style: TextStyle(color: colorOrange),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //
  //                       const SizedBox(height: 20),
  //
  //                       // Google / Facebook
  //                       Row(
  //                         mainAxisAlignment: MainAxisAlignment.center,
  //                         children: [
  //
  //                           // Sign In with Google
  //                           _buildSocialLoginButton(
  //                             context: context,
  //                             onPressed: () async {
  //                               Navigator.of(context).pop();
  //                               await _loginWithGoogle(context);
  //                             },
  //                             iconPath: iconGoogle,
  //                           ),
  //
  //                           const SizedBox(width: 20),
  //
  //                           // Sign In with facebook
  //                           _buildSocialLoginButton(
  //                             context: context,
  //                             onPressed: () {
  //                               // loginWithFacebook implementation would go here
  //                               Navigator.of(context).pop();
  //                             },
  //                             iconPath: iconFacebook,
  //                           ),
  //                         ],
  //                       ),
  //
  //                       SizedBox(height: 20),
  //
  //                       // Buttons Cancel / OK
  //                       Row(
  //                         mainAxisAlignment: MainAxisAlignment.center,
  //                         children: [
  //
  //                           // Cancel Button
  //                           MyTextButton(
  //                             text: 'Cancel',
  //                             onPressed: () {
  //                               Navigator.of(context).pop();
  //                             },
  //                           ),
  //
  //                           const SizedBox(width: 10),
  //
  //                           // OK Button
  //                           MyTextButton(
  //                             text: 'OK',
  //                             onPressed: () async {
  //                               bool loggedIn = await _loginWithEmail();
  //                               if(!mounted) return;
  //
  //                               if(loggedIn){
  //                                 Navigator.of(context).pop();
  //                               }
  //                             },
  //                           )
  //                         ],
  //                       ),
  //                       const SizedBox(height: 20),
  //
  //                     ],
  //                   ),
  //                 ),
  //               ),
  //             ),
  //           ),
  //         );
  //     },
  //   );
  // }
  // void _showEmailVerificationDialog(BuildContext context) {
  //   Timer? timer;
  //
  //   showDialog(
  //     context: context,
  //     barrierDismissible: false,
  //
  //     builder: (context) {
  //       timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
  //         final user = FirebaseAuth.instance.currentUser;
  //
  //         if (user == null) {
  //           timer.cancel();
  //           Navigator.of(context).pop();
  //           return;
  //         }
  //
  //         await user.reload(); // 🔥 Force server refresh
  //
  //         if (user.emailVerified) {
  //           timer.cancel();
  //           Navigator.of(context).pop(); // Close dialog
  //         }
  //       });
  //
  //       return AlertDialog(
  //         title: const Text("Email Verification"),
  //         content: const Text(
  //           "Please click the verification link sent to your email.\n\n"
  //               "This window will close automatically once verified.",
  //         ),
  //         shape: RoundedRectangleBorder(
  //           borderRadius: BorderRadius.circular(10),
  //           side: const BorderSide(
  //             color: Colors.blue, // Border color
  //             width: 2, // Border width
  //           ),
  //         ),
  //         backgroundColor: colorAppTitle,
  //         shadowColor: Colors.black,
  //         actions: [
  //           MyTextButton(
  //             text: "Resend Email",
  //             onPressed: () async {
  //               await _sendValidateEmail();
  //             },
  //           ),
  //           MyTextButton(
  //             text: "Cancel",
  //             onPressed: () async {
  //               timer?.cancel();
  //               await FirebaseAuth.instance.signOut();
  //               if(mounted){
  //                 Navigator.of(context).pop();
  //               }
  //             },
  //           )
  //         ],
  //       );
  //     },
  //   );
  // }
  // Future<void> _sendValidateEmail() async {
  //   final user = FirebaseAuth.instance.currentUser;
  //
  //   if (user == null) return;
  //
  //   try {
  //     await user.sendEmailVerification();   // 🔥 Forces server check
  //   } catch (e) {
  //     MyGlobalMessage.show("Error", e.toString(), MyMessageType.error);
  //   }
  // }
  Future<void> _validateUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      await user.reload();   // Forces server check
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        await FirebaseAuth.instance.signOut();
      }
    }
  }
  void _startTimeout(int sec) {
    _loadingTimer?.cancel();

    _loadingTimer = Timer(Duration(seconds: sec), () async {
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
              builder: (context, settings, user,__) {
                final isLoading = settings.isLoading || user.isLoading ||
                    snapshot.connectionState == ConnectionState.waiting ||
                    busyLoggingIn;
                final userLoggedIn = snapshot.hasData && user.userdata != null;

                String image = "";
                if (user.userdata != null) {
                  image = user.userdata!.imageURL ?? "";
                }

                ImageProvider profileImage;

                if (!isLoading && userLoggedIn && image.isNotEmpty == true) {
                  profileImage = NetworkImage(image);
                } else {
                  profileImage = AssetImage(iconProfile);
                }

                if (isLoading) {
                  _startTimeout(10);
                } else {
                  _cancelLoadingTimeout();
                }

                if (isLoading) {
                  return myProgressCircle();
                }
                return Scaffold(

                  backgroundColor: colorAppBackground,
                  body: Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                              children: [
                                AppBar(
                                  iconTheme: IconThemeData(color: colorIceBlue),
                                  backgroundColor: colorAppBar,
                                  leading: GestureDetector(
                                    onTap: () {
                                      if (userLoggedIn) toggleDrawer();
                                    },
                                    child: Icon(Icons.menu),
                                  ),
                                  title: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      myAppbarTitle("Limitless iOT"),
                                      myConnectionStatus(settings: settings),
                                    ],
                                  ),
                                  actions: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [

                                        // Profile Pic
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              right: 10, top: 2, bottom: 2),
                                          child: GestureDetector(
                                            onTap: () async {
                                              await _login(
                                                isLoading: isLoading,
                                                userLoggedIn: userLoggedIn,
                                                user: user,
                                              );
                                            },
                                
                                            // Profile Pic
                                            child: Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: Colors.white,
                                                    width: 0.5),
                                                // Clean white border
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.1),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: CircleAvatar(
                                                radius: 18,
                                                // Total size remains ~20 with the border
                                                backgroundColor: colorIceBlue,
                                                backgroundImage: profileImage,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                
                                !userLoggedIn
                                  ? Expanded(
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          GestureDetector(
                                            onTap: ()async{
                                              await _login(
                                                isLoading: isLoading,
                                                userLoggedIn: userLoggedIn,
                                                user: user,
                                              );
                                            },
                                            child: MyText(text: "Please  Log in")
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  :
                                // =========================
                                // Page Data
                                // =========================
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 20),
                                
                                        // Track Vehicle
                                        MyCustomTileWithPic(
                                          imagePath: iconFleet,
                                          header: 'Track',
                                          description: 'Track your vehicle as it moves inside and outside of your GeoFences',
                                          widget: TrackingPage(),
                                        ),
                                
                                        const SizedBox(height: 10),
                                
                                        // GeoFence
                                        const MyCustomTileWithPic(
                                          imagePath: iconGeoFence,
                                          header: 'GeoFence',
                                          description: 'Set all the fence perimeters where you would like to record refundable tax rebate',
                                          widget: GeoFencePage(),
                                        ),
                                
                                        const SizedBox(height: 10),
                                
                                        // Base Stations
                                        MyCustomTileWithPic(
                                          imagePath: iconBase,
                                          header: 'Base Stations',
                                          description: 'Add multiple base stations that acts as master network controllers.',
                                          widget: BaseStationPage(),
                                        ),
                                
                                        const SizedBox(height: 10),
                                
                                        // iOT Monitors
                                        const MyCustomTileWithPic(
                                          imagePath: iconIot,
                                          header: 'iOT Monitors',
                                          description: 'Add multiple iOT monitors for various use cases',
                                          widget: IotMonitorsPage(),
                                        ),
                                
                                        const SizedBox(height: 10),
                                
                                        // Iot Report
                                        const MyCustomTileWithPic(
                                          imagePath: iconReport,
                                          header: 'iOT Data Report',
                                          description: 'View all the iOT data history',
                                          widget: IotDataPage(),
                                        ),
                                
                                        SizedBox(height: 15)
                                      ],
                                    ),
                                  ),
                                ),
                                
                              ]),
                        ),

                        if (userLoggedIn)
                          AnimatedBuilder(
                              animation: _animationDraw,
                              builder: (context, child) {
                                bool isDrawerVisible = _animationDraw.value > -drawerWidth;
                                return Stack(
                                  children: [

                                    // =========================
                                    // Scrim (Tap to close)
                                    // =========================
                                    if(isDrawerVisible)
                                      Positioned.fill(
                                        child: GestureDetector(
                                          onTap: () => toggleDrawer(),
                                          // Closes the drawer when background is tapped
                                          behavior: HitTestBehavior.opaque,
                                          child: Container(
                                            color: Colors.black.withValues(
                                                alpha: 0.5), // Dim the background slightly
                                          ),
                                        ),
                                      ),

                                    // =========================
                                    // Menu Drawer
                                    // =========================

                                    Positioned(
                                        left: _animationDraw.value,
                                        top: 35,
                                        bottom: 15,
                                        child: Container(
                                          width: drawerWidth,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.only(
                                                topRight: Radius.circular(20),
                                                bottomRight: Radius.circular(20)
                                            ),
                                            color: colorTile,
                                          ),

                                          // Menu
                                          child: Column(
                                              children: [

                                                // Menu Header
                                                Container(
                                                  height: 120,
                                                  width: drawerWidth,
                                                  decoration: BoxDecoration(
                                                    gradient: myTileGradient(),
                                                    borderRadius: BorderRadius.only(topRight: Radius.circular(20),
                                                    ),
                                                  ),

                                                  // Menu Header
                                                  child: Column(
                                                    children: [

                                                      /// TOP ROW
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment
                                                            .spaceBetween,
                                                        crossAxisAlignment: CrossAxisAlignment
                                                            .center,
                                                        children: [
                                                          myAppbarTitle("Menu"),

                                                          Image.asset(
                                                            iconLimitlessLogo,
                                                            width: 50,
                                                            height: 40,
                                                            fit: BoxFit.contain,
                                                          ),
                                                        ],
                                                      ),

                                                      Spacer(),

                                                      /// BOTTOM INFO
                                                      Row(
                                                        crossAxisAlignment: CrossAxisAlignment
                                                            .start,
                                                        children: [
                                                          Column(
                                                            crossAxisAlignment: CrossAxisAlignment
                                                                .start,
                                                            children: [
                                                              MyText(
                                                                text: APP_VERSION,
                                                                color: Colors
                                                                    .grey,
                                                              ),
                                                              MyText(
                                                                text: user
                                                                    .userdata!.displayName,
                                                                color: Colors
                                                                    .grey,
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
                                                  child: Material(
                                                    type: MaterialType.transparency,
                                                    color: colorTile,
                                                    child: ListTileTheme(
                                                      data: ListTileThemeData(
                                                        tileColor: colorTile,
                                                        selectedTileColor: colorTile,
                                                      ),
                                                      child: ListView(
                                                    padding: EdgeInsets.zero,
                                                    children: [

                                                      // -------------------------
                                                      // (HEADING) Tracking
                                                      // -------------------------
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 10, left: 10),
                                                        child: MyTextHeader(
                                                          text: "Tracking",
                                                          color: colorMenuHeader,
                                                          fontsize: 18,
                                                          linecolor: colorAppBackground,
                                                        ),
                                                      ),

                                                      // Track
                                                      ListTile(
                                                        leading: Icon(
                                                            Icons.gps_fixed,
                                                            color: colorMenuIcons
                                                        ),
                                                        title: Text("Track",
                                                          style: TextStyle(
                                                              color: colorMenuText
                                                              ),
                                                        ),
                                                        onTap: () {
                                                          toggleDrawer();
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (
                                                                    context) =>
                                                                    TrackingPage()),
                                                          );
                                                        },
                                                      ),

                                                      // GeoFence
                                                      ListTile(
                                                        leading: Icon(
                                                          Icons.fence,
                                                            color: colorMenuIcons
                                                        ),
                                                        title: Text("GeoFence",
                                                            style: TextStyle(
                                                                color: colorMenuText)
                                                        ),
                                                        onTap: () {
                                                          toggleDrawer();
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (
                                                                    context) =>
                                                                    GeoFencePage()),
                                                          );
                                                        },
                                                      ),

                                                      // Tracking History
                                                      ListTile(
                                                        leading: Icon(
                                                            Icons.history,
                                                            color: colorMenuIcons
                                                        ),
                                                        title: Text(
                                                            "Tracking History",
                                                            style: TextStyle(
                                                                color: colorMenuText)
                                                        ),
                                                        onTap: () {
                                                          toggleDrawer();
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (
                                                                    context) =>
                                                                    TrackingHistoryPage()),
                                                          );
                                                        },
                                                      ),


                                                      // -------------------------
                                                      // (HEADING) IOT Monitor
                                                      // -------------------------
                                                      Padding(
                                                        padding: const EdgeInsets
                                                            .fromLTRB(
                                                            10, 20, 10, 0),
                                                        child: MyTextHeader(
                                                          text: "iOT",
                                                          color: colorMenuHeader,
                                                          fontsize: 18,
                                                          linecolor: colorAppBackground,
                                                        ),
                                                      ),

                                                      // Base Station
                                                      ListTile(
                                                        leading: Icon(
                                                            Icons.cell_tower,
                                                            color: colorMenuIcons
                                                        ),
                                                        title: Text(
                                                            "Base Station",
                                                            style: TextStyle(
                                                                color: colorMenuText)
                                                        ),
                                                        onTap: () {
                                                          toggleDrawer();
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (
                                                                    context) =>
                                                                    BaseStationPage()),
                                                          );
                                                        },
                                                      ),

                                                      // IOT Monitors
                                                      ListTile(
                                                        leading: Icon(
                                                            Icons.monitor,
                                                            color: colorMenuIcons
                                                        ),
                                                        title: Text(
                                                          "iOT Monitors",
                                                          style: TextStyle(
                                                              color: colorMenuText),
                                                        ),
                                                        onTap: () {
                                                          toggleDrawer();
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (
                                                                    context) =>
                                                                    IotMonitorsPage()),
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
                                                          style: TextStyle(
                                                              color: colorMenuText),
                                                        ),
                                                        onTap: () {
                                                          toggleDrawer();
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (
                                                                    context) =>
                                                                    IotDataPage()),
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
                                                          style: TextStyle(
                                                              color: colorMenuText),
                                                        ),
                                                        onTap: () {
                                                          toggleDrawer();
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (
                                                                    context) =>
                                                                    OperatorsPage()),
                                                          );
                                                        },
                                                      ),

                                                      // -------------------------
                                                      // (HEADING) Settings
                                                      // -------------------------
                                                      Padding(
                                                        padding: const EdgeInsets
                                                            .fromLTRB(
                                                            10, 20, 10, 0),
                                                        child: MyTextHeader(
                                                          text: "Settings",
                                                          color: colorMenuHeader,
                                                          fontsize: 18,
                                                          linecolor: colorAppBackground,
                                                        ),
                                                      ),

                                                      // Settings
                                                      ListTile(
                                                        leading: Icon(
                                                            Icons.settings,
                                                            color: colorMenuIcons
                                                        ),
                                                        title: Text("Settings",
                                                            style: TextStyle(
                                                                color: colorMenuText)
                                                        ),
                                                        onTap: () {
                                                          toggleDrawer();
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (
                                                                    context) =>
                                                                    SettingsPage(
                                                                        userId: user
                                                                            .userdata!
                                                                            .userID)
                                                            ),
                                                          );
                                                        },
                                                      ),

                                                      SizedBox(height: 5,)
                                                    ],
                                                  ),
                                                    ),
                                                  ),
                                                ),
                                              ]
                                          ),
                                        )
                                    ),
                                  ],
                                );
                              }
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
