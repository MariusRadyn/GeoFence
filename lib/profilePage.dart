import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/signupPage.dart';

import 'firebase.dart';
import 'homePage.dart';
// import 'package:teamplayerwebapp/theme/theme_manager.dart';
// import 'package:teamplayerwebapp/utils/globalData.dart';
// import 'package:teamplayerwebapp/utils/helpers.dart';
// import 'package:teamplayerwebapp/utils/firebase.dart';

class profilePage extends StatefulWidget {
  const profilePage({super.key});

  @override
  State<profilePage> createState() => _profilePageState();
}

class _profilePageState extends State<profilePage> {
  TextEditingController _usernameControl = TextEditingController();
  TextEditingController _emailControl = TextEditingController();
  TextEditingController _Control = TextEditingController();
  TextEditingController _pwControl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
      ),
      body: Padding(
        padding: EdgeInsets.only(left: 20, right: 20),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Email Address
              textInputWidget(
                controller: _usernameControl,
                hintText: "Username",
                width: 300,
              ),
              SizedBox(height: 20),
              // Password
              textInputWidget(
                controller: _emailControl,
                hintText: "Email",
                isPasswordField: true,
                width: 300,
              ),
              SizedBox(height: 20),

              // Login Button
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        TextButton(
                          style: ButtonStyle(
                            minimumSize: WidgetStatePropertyAll(Size(150, 50)),
                            backgroundColor:
                                WidgetStatePropertyAll(COLOR_ORANGE),
                          ),
                          child: Text(
                            "Login",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          onPressed: () {
                            login();
                          },
                        ),
                      ]),
                ],
              ),

              SizedBox(height: 20),

              // Register
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Dont have an account?"),
                  SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => signupPage()),
                      );
                    },
                    child: Text(
                      "Register",
                      style: TextStyle(color: COLOR_ORANGE),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void login() async {
    FirebaseAuthService _auth = FirebaseAuthService();

    String email = _emailControl.text;
    String password = _pwControl.text;

    try {
      User? user = await _auth.fireAuthSignIn(email, password);

      if (user != null) {
        userData.userID = user.uid;
        userData.email = user.email;
        userData.isLoggedIn = true;

        print('User logged in');

        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HomePage(),
            ));
      } else {
        print(userData.errorMsg);
        MyMessageBox(
                header: "Login Error",
                message: userData.errorMsg,
                image: "assets/images/warning.png")
            .dialogBuilder(context);
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
