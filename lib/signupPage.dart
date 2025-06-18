import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/homePage.dart';
//import 'package:teamplayerwebapp/theme/theme_manager.dart';
import 'package:geofence/utils.dart';
//import 'package:teamplayerwebapp/utils/helpers.dart';

class signupPage extends StatefulWidget {
  const signupPage({super.key});

  @override
  State<signupPage> createState() => _signupPageState();
}

class _signupPageState extends State<signupPage> {
  final FirebaseAuthService _auth = FirebaseAuthService();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _pw2Controller = TextEditingController();

  @override
  void dispose() {
    _userController.dispose();
    _emailController.dispose();
    _pwController.dispose();
    _pw2Controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //UserData _userData = Provider.of<UserData>(context, listen: false);
    UserData? userData = UserDataService().userdata;

    return Scaffold(
      appBar: AppBar(
        title: Text('Sign Up'),
      ),
      body: Padding(
        padding: EdgeInsets.only(left: 20, right: 20),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Email Address
              MyTextFormField(
                controller: _emailController,
                hintText: "Enter Email Address",
              ),

              SizedBox(height: 20),

              // Password
              MyTextFormField(
                controller: _pwController,
                hintText: "Password",
                isPasswordField: true,
              ),

              SizedBox(height: 20),

              // Confirm Password
              MyTextFormField(
                controller: _pw2Controller,
                hintText: "Confirm Password",
                isPasswordField: true,
              ),

              SizedBox(height: 20),

              // Signup Button
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.only(
                        left: 80, right: 80, top: 10, bottom: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      color: COLOR_ORANGE,
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          TextButton(
                            child: Text(
                              "Register",
                              style: TextStyle(color: Colors.white),
                            ),
                            onPressed: () {
                              if (_pwController.text != _pw2Controller.text) {
                                Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => MyDialogWidget(
                                          header: "Password Error",
                                          message:
                                              'Passwords do not match\rPlease re-enter your password',
                                          but1Text: "OK",
                                          but2Text: "Cancel",
                                          onPressedBut1:
                                              Navigator.of(context).pop,
                                          onPressedBut2:
                                              Navigator.of(context).pop,
                                        )));
                              } else {
                                signUp(userData);
                              }
                            },
                          ),
                        ]),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void signUp(UserData? userData) async {
    String username = _userController.text;
    String email = _emailController.text;
    String password = _pwController.text;

    User? user = await _auth.fireAuthCreateUser(context, email, password);

    if (user != null) {
      userData?.userID = user.uid;
      userData?.displayName = username;

      printMsg('User created successfully');

      fireDbCreateUser(user);

      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(),
          ));
    } else {
      printMsg('Error creating user');
    }
  }
}
