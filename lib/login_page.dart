import 'dart:async';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

import 'firebase.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwController2 = TextEditingController();
  final TextEditingController _userController = TextEditingController();

  bool busyLoggingIn = false;

  @override
  void initState() {
    super.initState();
    _validateUser();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
    });
  }

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

  String _getGoogleError(dynamic error) {
    if (error == null) return "Unknown error";

    // Platform-specific error (most common)
    if (error is PlatformException) {
      return error.message ?? "Google sign-in failed";
    }

    if (error is FirebaseAuthException) {
      return error.message ?? "Auth error";
    }

    if (error is GoogleSignInException) {
      return error.description ?? "Google Sign in Error";
    }

    // General fallback
    return error.toString().replaceFirst("Exception: ", "");
  }

  void _signUpScreen (){
    double width = MediaQuery.of(context).size.width * 0.8;
    double height = MediaQuery.of(context).size.height * 0.6;

    _emailController.text = "";
    _pwController.text = "";
    _pwController2.text = "";
    _userController.text = "";

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: SizedBox(
            width: width > 500 ? 500 : width, // Custom width
            height: height > 600 ? 600 : height, // Custom height
            child: Container(
              decoration: BoxDecoration(
                  gradient: myTileGradient(),
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
                      backgroundColor: colorAppBackground,
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
                      backgroundColor: colorAppBackground,
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
                      backgroundColor: colorAppBackground,
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
                      backgroundColor: colorAppBackground,
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
                      myTextButton(
                        text: 'Cancel',
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),

                      SizedBox(width: 10),

                      // OK Button
                      myTextButton(
                        text:'OK',
                        onPressed: () async {
                          final user = await _signUp();

                          if (user != null) {
                            if(!mounted) return;
                            // ignore: use_build_context_synchronously
                            Navigator.of(context).pop(); // close current dialog FIRST
                            
                            await _sendValidateEmail();
                            if(!mounted) return;

                            // ignore: use_build_context_synchronously
                            _showEmailVerificationDialog(context);
                          }
                        },
                      ),
                    ],
                  ),
                ]),
            ),
          ));
      },
    );
  }
  Future<User?> _signUp() async {
    UserDataService userService = context.read<UserDataService>();
    AuthResult result = AuthResult();

    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      MyGlobalMessage.show("Info", 'Please enter email and password.', MyMessageType.info);
      return null;
    }
    if (!_emailController.text.contains('@')) {
      MyGlobalMessage.show("Info", 'Please enter valid email address.', MyMessageType.info);
      return null;
    }
    if (_userController.text.isEmpty) {
      MyGlobalMessage.show("Info", 'Please enter username.', MyMessageType.info);
      return null;
    }
    if (_pwController.text != _pwController2.text) {
      MyGlobalMessage.show("Info", 'Passwords dont match.', MyMessageType.info);
      return null;
    }

    try {
      result = await firebaseAuthService.fireAuthCreateUserWithEmail(
          context,
          _emailController.text,
          _pwController.text
      );

      if (result.isSuccess && result.user != null) {
        final doc = await FirebaseFirestore.instance
            .collection(collectionUsers)
            .doc(result.user!.uid)
            .get();

        // Create user ONLY if it does not exist
        if (!doc.exists) {
          userService.create(
              UserData(
                displayName: _userController.text,
                email: _emailController.text,
                emailValidated: result.user!.emailVerified,
              ),
              uid: result.user!.uid
          );

          printDebugMsg('User Created');
        }

        return result.user;

      } else {
        if(result.code != null){
          MyGlobalMessage.show("Login", result.code!, MyMessageType.warning);
        } else {
          MyGlobalMessage.show("Login", result.exception.toString(), MyMessageType.warning);
        }

        userService.logout();
      }
    } catch (e) {
      MyGlobalMessage.show("Error", result.exception.toString(), MyMessageType.error);
    }
    return null;
  }
  Future<bool> _resetPasswordWithEmail() async {
    UserDataService userService = context.read<UserDataService>();

    if (_emailController.text.isEmpty) {
      MyGlobalMessage.show("Info", 'Please enter email address.', MyMessageType.info);
      return false;
    }
    if (!_emailController.text.contains('@')) {
      MyGlobalMessage.show("Info", 'Please enter a valid email address.', MyMessageType.info);
      return false;
    }

    try {
      if(await firebaseAuthService.fireAuthResetPassword(context, _emailController.text)) {
        if(userService.userdata != null){
          userService.isUserLoggedIn = false;
        }
        printDebugMsg('Password Reset');
        return true;
      }
      else {
        MyGlobalMessage.show("Error", 'Failed to reset password', MyMessageType.error);
        return false;
      }

    } catch (e) {
      MyGlobalMessage.show("Error", '$e', MyMessageType.error);
      return false;
    }
  }
  Future<void> _sendValidateEmail() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      await user.sendEmailVerification();   // 🔥 Forces server check
    } catch (e) {
      MyGlobalMessage.show("Error", e.toString(), MyMessageType.error);
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
          if(!mounted) return;
          
          if (user.emailVerified) {
            timer.cancel();
            // ignore: use_build_context_synchronously
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
          backgroundColor: colorAppTitle,
          shadowColor: Colors.black,
          actions: [
            myTextButton(
              text: "Resend Email",
              onPressed: () async {
                await _sendValidateEmail();
              },
            ),
            myTextButton(
              text: "Cancel",
              onPressed: () async {
                timer?.cancel();
                await FirebaseAuth.instance.signOut();
                if(mounted){
                  // ignore: use_build_context_synchronously
                  Navigator.of(context).pop();
                }
              },
            )
          ],
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
  Future<bool> _loginWithEmail() async {
    UserDataService userService = context.read<UserDataService>();
    userService.errorMsg = "";
    userService.firebaseError = false;

    if (_emailController.text.isEmpty || _pwController.text.isEmpty) {
      MyGlobalMessage.show("Login", 'Please enter email and password.', MyMessageType.info);
      return false;
    }
    if (!_emailController.text.contains('@')) {
      MyGlobalMessage.show("Login", 'Please enter a valid email address.', MyMessageType.info);
      return false;
    }

    try {
      setState(() {
        busyLoggingIn = true;
      });

      AuthResult result = await firebaseAuthService.fireAuthSignInWithEmail(
        context,
        _emailController.text,
        _pwController.text,
      );

      await userService.load();

      setState(() {
        busyLoggingIn = false;
      });

      // Logged In
      if (result.isSuccess) {
        if(userService.userdata != null){
          userService.isUserLoggedIn = true;
        }
      } else {
        // Logged ERROR
        if(userService.userdata != null){
          userService.isUserLoggedIn = false;
        }

        if(result.code != null){
          MyGlobalMessage.show("Login", result.code!, MyMessageType.warning);
        } else {
          MyGlobalMessage.show("Login", result.exception.toString(), MyMessageType.warning);
        }
        return false;
      }
    } catch (e) {
      MyGlobalMessage.show("Error(LoginWithEmail):", '$e', MyMessageType.debug);
      return false;
    }
    return true;
  }
  Future<bool> _loginWithGoogle(BuildContext context) async {
    UserDataService userService = context.read<UserDataService>();
    userService.errorMsg = "";
    userService.firebaseError = false;

    try {
      setState(() {
        busyLoggingIn = true;
      });

      AuthResult result = await firebaseAuthService.signInWithGoogle();
      await userService.load();

      if(result.isSuccess){
        final doc = await FirebaseFirestore.instance
            .collection(collectionUsers)
            .doc(result.user!.uid)
            .get();


        // Create user ONLY if it does not exist
        if (!doc.exists) {
          if (result.user != null) {
            userService.create(
                UserData(
                  displayName:  result.user?.displayName ?? "",
                  email: result.user?.email ?? "",
                  emailValidated: true,
                  imageURL: result.user?.photoURL ?? "",
                ),
                uid: result.user!.uid
            );

            setState(() {
              userService.isUserLoggedIn = true;
              busyLoggingIn = true;
            });

          } else {
            if(!result.user!.emailVerified){
              MyGlobalMessage.show("Warning", "Email address not verified", MyMessageType.warning);
              return false;
            }
            else {

              MyGlobalMessage.show("Warning", "User Credentials not found", MyMessageType.warning);
              return false;
            }
          }
        }
      }
      else{
        String err = _getGoogleError(result.exception);
        MyGlobalMessage.show("Error", err, MyMessageType.error);

        setState(() {
          busyLoggingIn = false;
        });

        return false;
      }
    } catch (e) {
      setState(() {
        busyLoggingIn = false;
      });

      MyGlobalMessage.show("Error(LoginWithGoogle)", '$e', MyMessageType.debug);
      return false;
    }

    if(!mounted) return false;
    setState(() {
      busyLoggingIn = false;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title:
            MyText(
              text: "Login",
              fontsize: 20,
            ),


      ),

      backgroundColor: colorAppBackground,
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF042C3A),
                  Color(0xFF063F52),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // Honeycomb overlay
          Opacity(
            opacity: 0.08, // subtle
            child: CustomPaint(
              size: Size.infinite,
              painter: HexagonPainter(),
            ),
          ),

          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MyText(text: "Enter Credentials")
                    ],
                  ), 
                 
                  SizedBox(height: 40),

                  // Inputs
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        MyTextFormField(
                          inputType: TextInputType.emailAddress,
                          backgroundColor: colorAppBackground,
                          foregroundColor: Colors.white,
                          controller: _emailController,
                          //hintText: "Enter Email Address",
                          labelText: "Email",
                          valueFontSize: 14,

                        ),

                        SizedBox(height: 20),

                        MyTextFormField(
                           foregroundColor: Colors.white,
                           backgroundColor: colorAppBackground,
                           controller: _pwController,
                           //hintText: "Enter Password",
                           labelText: "Password",
                           isPasswordField: true,
                           valueFontSize: 14,
                         ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20),

                  //Reset Password
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
                          if(await _resetPasswordWithEmail()){
                            MyGlobalMessage.show("Check email", "Please check your email and follow the instructions", MyMessageType.info);
                          }
                          //Navigator.of(context).pop();
                        },
                        child: const Text(
                          "Reset",
                          style: TextStyle(color: colorOrange),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 20),

                  // Sign up
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
                          _signUpScreen();
                        },
                        child: const Text(
                          "Sign up",
                          style: TextStyle(color: colorOrange),
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
                          final loggedin = await _loginWithGoogle(context);
                          if(!mounted) return;
                          
                          if(loggedin){
                            // ignore: use_build_context_synchronously
                            Navigator.of(context).pop();
                          }
                        },
                        iconPath: iconGoogle,
                      ),

                      const SizedBox(width: 20),

                      // Sign In with facebook
                      _buildSocialLoginButton(
                        context: context,
                        onPressed: () {
                          // loginWithFacebook implementation would go here
                          //Navigator.of(context).pop();
                          MyGlobalMessage.show("Oops!","Not Implemented Yet",MyMessageType.warning );
                        },
                        iconPath: iconFacebook,
                      ),
                    ],
                  ),

                  SizedBox(height: 20),

                  // Buttons Cancel / OK
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      // Cancel Button
                      myTextButton(
                        text: 'Cancel',
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),

                      const SizedBox(width: 10),

                      // OK Button
                      myTextButton(
                        text: 'OK',
                        onPressed: () async {
                          bool loggedIn = await _loginWithEmail();
                          if(!mounted) return;

                          if(loggedIn){
                            // ignore: use_build_context_synchronously
                            Navigator.of(context).pop();
                          }
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Logo
                  Image.asset(iconLimitlessLogo, height: 100),

                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
