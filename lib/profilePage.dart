import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/signupPage.dart';
import 'package:provider/provider.dart';
import 'firebase.dart';
import 'homePage.dart';

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
    //UserData _userData = Provider.of<UserData>(context, listen: false);
    UserData? _userData = UserDataService().userdata;

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
              MyTextFormField(
                controller: _usernameControl,
                hintText: "Username",
                width: 300,
              ),
              SizedBox(height: 20),
              // Password
              MyTextFormField(
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
                            login(_userData);
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

  void login(UserData? _userData) async {
    FirebaseAuthService _auth = FirebaseAuthService();


    try {
      //User? user = await _auth.fireAuthSignIn(context, _emailControl.text, _pwControl.text);

      if (_userData != null && _userData.isLoggedIn) {

        print('User logged in');

        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HomePage(),
            ));
      } else {
        print(_userData!.errorMsg);
        myMessageBox(context, _userData.errorMsg);
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
