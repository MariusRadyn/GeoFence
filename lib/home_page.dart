import 'dart:async';

//import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/app_flavor.dart';
import 'package:geofence/iot_data_summary_page.dart';
//import 'package:geofence/firebase.dart';
import 'package:geofence/contact_us_page.dart';
import 'package:geofence/login_page.dart';
import 'package:geofence/legal_documents_page.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/operators_page.dart';
import 'package:geofence/Tracking_page.dart';
import 'package:geofence/base_station_page.dart';
import 'package:geofence/geo_fence_page.dart';
import 'package:geofence/profile_page.dart';
import 'package:geofence/settings_page.dart';
import 'package:geofence/order_history_page.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/shop_setup_page.dart';
import 'package:geofence/tracking_history_page.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/wages_summary_page.dart';
import 'package:geofence/whats_new_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'iot_monitors_page.dart';

class HomePage extends StatefulWidget {
  final bool openProfileOnLaunch;

  const HomePage({super.key, this.openProfileOnLaunch = false});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controllerDraw;
  late Animation<double> _animationDraw;
  final double drawerWidth = 250;
  Timer? _loadingTimer;
  bool busyLoggingIn = false;
  bool _profileLaunchHandled = false;
  String? _profileLoadRequestedForUid;
  String _versionLabel = '';

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
    WidgetsBinding.instance.addObserver(this);
    _loadVersionLabel();
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

  Future<void> _loadVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _versionLabel = '${info.version}+${info.buildNumber}';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
  List<Widget> _buildHomeTiles() {
    final tiles = <Widget>[];

    void addTile(Widget tile) {
      if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 10));
      tiles.add(tile);
    }

    addTile(
      MyCustomTileWithPic(
        imagePath: iconWhatsNew,
        header: "What's New",
        description: 'Latest updates, features, and improvements',
        widget: const WhatsNewPage(),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WhatsNewPage()),
          );
        },
      ),
    );

    if (AppConfig.showLiveTracking) {
      addTile(
        MyCustomTileWithPic(
          imagePath: iconFleet,
          header: 'Track',
          description:
              'Track your vehicle as it moves inside and outside of your GeoFences',
          widget: TrackingPage(),
        ),
      );
    }

    if (AppConfig.showBaseStations) {
      addTile(
        MyCustomTileWithPic(
          imagePath: iconBase,
          header: 'Base Stations',
          description:
              'Add multiple base stations that acts as master network controllers.',
          widget: BaseStationPage(),
        ),
      );
    }

    if (AppConfig.showIotMonitors) {
      addTile(
        const MyCustomTileWithPic(
          imagePath: iconIot,
          header: 'iOT Monitors',
          description: 'Add multiple iOT monitors for various use cases',
          widget: IotMonitorsPage(),
        ),
      );
    }

    if (AppConfig.showIotDataReport) {
      addTile(
        const MyCustomTileWithPic(
          imagePath: iconReport,
          header: 'iOT Data Report',
          description: 'View all the iOT data history',
          widget: IotDataPage(),
        ),
      );
    }

    if (AppConfig.addWages) {
      addTile(
        MyCustomTileWithPic(
          imagePath: iconWages,
          header: 'Wages',
          description: 'View operator wage summaries from IoT distance logs',
          widget: const WagesPage(),
        ),
      );
    }

    if (AppConfig.addShop) {
      addTile(
        const MyCustomTileWithPic(
          imagePath: iconShop,
          header: 'Online Shop',
          description: 'Browse Limitless IoT products, Bob Pay and Bob Go',
          widget: ShopPage(),
        ),
      );
    }

    return tiles;
  }

  void _openDrawerPage(Widget page) {
    // Close the drawer first, then push — avoids jank from animating both at once.
    if (_controllerDraw.isCompleted || _controllerDraw.value > 0) {
      _controllerDraw.reverse();
    }
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
    });
  }

  List<Widget> _buildDrawerItems(UserDataService user) {
    final items = <Widget>[];

    void open(Widget page) => _openDrawerPage(page);

    ListTile drawerTile({
      required IconData icon,
      required String title,
      required VoidCallback onTap,
    }) {
      return ListTile(
        leading: Icon(icon, color: colorMenuIcons),
        title: Text(title, style: TextStyle(color: colorMenuText)),
        onTap: onTap,
      );
    }

    Widget heading(String text, {bool first = false}) {
      return Padding(
        padding: first
            ? const EdgeInsets.only(top: 10, left: 10)
            : const EdgeInsets.fromLTRB(10, 20, 10, 0),
        child: MyTextHeader(
          text: text,
          color: colorMenuHeader,
          fontsize: 18,
          linecolor: colorAppBackground,
        ),
      );
    }

    final showTrackingSection = AppConfig.showLiveTracking ||
        AppConfig.showGeoFenceSetup ||
        AppConfig.showTrackingHistory;
    if (showTrackingSection) {
      items.add(heading('Tracking', first: true));
      if (AppConfig.showLiveTracking) {
        items.add(drawerTile(
          icon: Icons.gps_fixed,
          title: 'Track',
          onTap: () => open(TrackingPage()),
        ));
      }
      if (AppConfig.showGeoFenceSetup) {
        items.add(drawerTile(
          icon: Icons.fence,
          title: 'GeoFence',
          onTap: () => open(const GeoFencePage()),
        ));
      }
      if (AppConfig.showTrackingHistory) {
        items.add(drawerTile(
          icon: Icons.history,
          title: 'Tracking History',
          onTap: () => open(const TrackingHistoryPage()),
        ));
      }
    }

    final showIotSection = AppConfig.showBaseStations ||
        AppConfig.showIotMonitors ||
        AppConfig.showIotDataReport;
    if (showIotSection) {
      items.add(heading('iOT', first: !showTrackingSection));
      if (AppConfig.showBaseStations) {
        items.add(drawerTile(
          icon: Icons.cell_tower,
          title: 'Base Station',
          onTap: () => open(BaseStationPage()),
        ));
      }
      if (AppConfig.showIotMonitors) {
        items.add(drawerTile(
          icon: Icons.monitor,
          title: 'iOT Monitors',
          onTap: () => open(const IotMonitorsPage()),
        ));
      }
      if (AppConfig.showIotDataReport) {
        items.add(drawerTile(
          icon: Icons.dataset,
          title: 'iOT Data',
          onTap: () => open(const IotDataPage()),
        ));
      }
    }

    final showGeneralSection = AppConfig.showOperators ||
        AppConfig.showWages ||
        AppConfig.showShop;
    final userIsDeveloper = user.userdata?.isDeveloper == true;
    final showSetupShop = enableSetupShop || userIsDeveloper;
    // Setup always shown so Legal Documents remains reachable.
    const showSetupSection = true;

    if (showGeneralSection) {
      items.add(heading('General', first: !showTrackingSection && !showIotSection));
      if (AppConfig.showOperators) {
        items.add(drawerTile(
          icon: Icons.person,
          title: 'Operators',
          onTap: () => open(const OperatorsPage()),
        ));
      }
      if (AppConfig.showWages) {
        items.add(drawerTile(
          icon: Icons.attach_money_sharp,
          title: 'Wages',
          onTap: () => open(const WagesPage()),
        ));
      }
      if (AppConfig.showShop) {
        items.add(drawerTile(
          icon: Icons.storefront_outlined,
          title: 'Online Shop',
          onTap: () => open(const ShopPage()),
        ));
        items.add(drawerTile(
          icon: Icons.receipt_long_outlined,
          title: 'Order History',
          onTap: () => open(const OrderHistoryPage()),
        ));
      }
    }

    if (showSetupSection) {
      items.add(heading(
        'Setup',
        first: !showTrackingSection && !showIotSection && !showGeneralSection,
      ));
      if (AppConfig.showSettings) {
        items.add(drawerTile(
          icon: Icons.settings,
          title: 'Settings',
          onTap: () => open(SettingsPage(userId: user.userdata!.userID)),
        ));
      }
      if (showSetupShop) {
        items.add(drawerTile(
          icon: Icons.store_mall_directory_outlined,
          title: 'Setup Shop',
          onTap: () => open(const ShopSetupPage()),
        ));
      }
      items.add(drawerTile(
        icon: Icons.gavel_outlined,
        title: 'Legal Documents',
        onTap: () => open(const LegalDocumentsPage()),
      ));
    }

    items.add(drawerTile(
      icon: Icons.lightbulb_outline,
      title: 'Contact Us',
      onTap: () => open(const ContactUsPage()),
    ));

    items.add(const SizedBox(height: 5));
    return items;
  }

  Future<void> _openProfileOnLaunch() async {
    final userService = context.read<UserDataService>();
    await userService.load();

    if (!mounted) return;

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
    );
  }

  Future<void> _login({
    required UserDataService user,
  }) async {
    // Prefer live auth/profile state — tap-time flags go stale during await.
    if (FirebaseAuth.instance.currentUser != null && user.userdata == null) {
      await user.load();
    }
    if (!mounted) return;

    final fullyLoggedIn =
        FirebaseAuth.instance.currentUser != null && user.userdata != null;

    if (fullyLoggedIn) {
      if (user.userdata?.emailValidated != true) {
        MyGlobalMessage.show(
          'Verify Email',
          'Please open your email.\nClick on the verify link',
          MyMessageType.info,
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      );
      return;
    }

    // Not signed in (or profile missing) — always open credentials.
    if (busyLoggingIn) {
      setState(() => busyLoggingIn = false);
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
    );
    if (!mounted) return;
    await user.load();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final user = context.read<UserDataService>();
    if (user.isLoggingOut || FirebaseAuth.instance.currentUser == null) {
      return;
    }
    user.load();
    context.read<SettingsService>().load();
  }

  void _startTimeout(int sec) {
    // Already armed — don't restart on every rebuild.
    if (_loadingTimer != null) return;

    _loadingTimer = Timer(Duration(seconds: sec), () {
      if (!mounted) return;
      // Never sign out on a load timeout — that forced re-login on web.
      setState(() {
        busyLoggingIn = false;
      });
      MyGlobalMessage.show(
        "Timeout",
        "Loading took too long. Try again.",
        MyMessageType.warning,
      );
    });
  }
  void _cancelLoadingTimeout() {
    _loadingTimer?.cancel();
    _loadingTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return
      StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {

          return Consumer2<SettingsService, UserDataService>(
              builder: (context, settings, user,__) {
                final authWaiting =
                    snapshot.connectionState == ConnectionState.waiting;
                final authUser = snapshot.data;
                final profilePending =
                    authUser != null && user.userdata == null;
                // Only block UI while a load is actually in progress — not when
                // auth exists but Firestore profile is missing/failed (that used
                // to leave the spinner up until the 10s timeout).
                final profileSyncing =
                    profilePending && (user.isLoading || settings.isLoading);
                final showLoadingOverlay =
                    authWaiting || busyLoggingIn || profileSyncing;
                final userLoggedIn =
                    authUser != null && user.userdata != null;

                String image = "";
                if (user.userdata != null) {
                  image = user.userdata!.imageURL ?? "";
                }

                if (showLoadingOverlay) {
                  _startTimeout(20);
                } else {
                  _cancelLoadingTimeout();
                }

                if (authUser == null) {
                  _profileLoadRequestedForUid = null;
                  if (busyLoggingIn) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => busyLoggingIn = false);
                    });
                  }
                  _cancelLoadingTimeout();
                } else if (!user.isLoggingOut &&
                    user.userdata == null &&
                    !user.isLoading &&
                    _profileLoadRequestedForUid != authUser.uid) {
                  _profileLoadRequestedForUid = authUser.uid;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (user.isLoggingOut ||
                        FirebaseAuth.instance.currentUser == null) {
                      return;
                    }
                    user.load();
                    settings.load();
                  });
                }

                if (widget.openProfileOnLaunch && !_profileLaunchHandled) {
                  _profileLaunchHandled = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _openProfileOnLaunch();
                  });
                }

                return Scaffold(

                  backgroundColor: const Color(0xFF020617),
                  body: homeBackground(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: Column(
                              children: [
                                AppBar(
                                  iconTheme: IconThemeData(color: colorIceBlue),
                                  backgroundColor: Colors.transparent,
                                  elevation: 0,
                                  scrolledUnderElevation: 0,
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
                                              child: NetworkCircleAvatar(
                                                imageUrl: userLoggedIn ? image : null,
                                                radius: 18,
                                                backgroundColor: colorIceBlue,
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

                                        ..._buildHomeTiles(),

                                        const SizedBox(height: 15),
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
                                                          Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 5),
                                                            child: myAppbarTitle("Menu"),
                                                          ),

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
                                                              Padding(
                                                                padding: const EdgeInsets.symmetric(horizontal: 5.0),
                                                                child: MyText(
                                                                  text: _versionLabel.isNotEmpty
                                                                      ? _versionLabel
                                                                      : APP_VERSION,
                                                                  color: Colors
                                                                      .grey,
                                                                ),
                                                              ),
                                                              Padding(
                                                                padding: const EdgeInsets.symmetric(horizontal: 5.0),
                                                                child: MyText(
                                                                  text: user
                                                                      .userdata!.displayName,
                                                                  color: Colors
                                                                      .grey,
                                                                ),
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
                                                        children:
                                                            _buildDrawerItems(user),
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
                        if (showLoadingOverlay)
                          Positioned.fill(
                            child: ColoredBox(
                              color: const Color(0xFF020617).withValues(alpha: 0.92),
                              child: Center(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 32),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 32,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorAppTitle,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      myProgressCircle(),
                                      if (profilePending) ...[
                                        const SizedBox(height: 16),
                                        const MyText(
                                          text: "Logging in...",
                                          color: Colors.white,
                                          fontsize: 16,
                                        ),
                                        const SizedBox(height: 8),
                                        const MyText(
                                          text:
                                              "Please wait while we set up your account.",
                                          color: Colors.grey,
                                          fontsize: 13,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }
          );    // Not logged in
        },
      );
  }
}
