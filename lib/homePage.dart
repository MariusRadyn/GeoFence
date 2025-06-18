import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/TrackingPage.dart';
import 'package:geofence/geofencePage.dart';
import 'package:geofence/profilePage.dart';
import 'package:geofence/settingsPage.dart';
import 'package:geofence/trackingHistoryPage.dart';
//import 'package:geofence/TrackingPage.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'vehiclesPage.dart';

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


  @override
  void initState() {
    super.initState();

    if(UserDataService().userdata != null) {
      setState(() {
        UserDataService().userdata!.isLoggedIn = true;
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        title: MyAppbarTitle('GeoFence V1.0'),
        actions: [
          Consumer2<UserDataService, SettingsService>(
            builder: (context, userData, settings, child) {

              if (userData.userdata == null) {
                if ((settings.isLoading && userData.isLoading)) {
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
              }

              if (userData.firebaseError){
                //GlobalSnackBar.show("Firebase Error");
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
                          if (userData.userdata != null){
                           if( userData.userdata!.isLoggedIn) {
                             // GlobalMsg.show(
                             //     "Profile", "Userid: ${userData.userdata?.userID}\n"
                             //     "UserName: ${userData.userdata?.displayName}\n"
                             //      "email: ${userData.userdata?.email}"
                             // );
                             Navigator.push(
                                 context,
                                 MaterialPageRoute(
                                 builder: (context) => profilePage(),
                              ),
                             );
                          } else {
                            showLoginScreen(context);
                            }
                          }
                          else{
                            showLoginScreen(context);
                          }
                        },

                        // Profile Pic
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundImage: userData.userdata?.isLoggedIn == true
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
      backgroundColor: APP_BACKGROUND_COLOR,
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 50),

            MyCustomTileWithPic(
              imagePath: 'assets/track.jpg',
              header: 'Track',
              description: 'Track your vehicle as it moves inside and outside of your GeoFences',
              widget: TrackingPage(),
            ),

            const SizedBox(height: 10),

            const MyCustomTileWithPic(
              imagePath: 'assets/geofence.jpg',
              header: 'GeoFence',
              description: 'Set all the fence perimeters where you would like to record refundable tax rebate',
              widget: GeoFencePage(),
            ),

            const SizedBox(height: 10),

            const MyCustomTileWithPic(
              imagePath: 'assets/red_pickup2.png',
              header: 'Vehicles',
              description: 'Add all the vehicles in your fleet',
              widget: VehiclesPage(),
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
    );
  }
}
