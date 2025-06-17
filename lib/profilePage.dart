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
  TextEditingController _displaynameControl = TextEditingController();
  TextEditingController _emailController = TextEditingController();
  TextEditingController _Control = TextEditingController();
  TextEditingController _pwControl = TextEditingController();

  @override
  void initState() {
    super.initState();

    if(UserDataService().userdata != null) {
      setState(() {
        if(UserDataService().userdata != null){
          _displaynameControl.text =  UserDataService().userdata!.displayName;
          _emailController.text =  UserDataService().userdata!.email;
        }
      });
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
                     ? Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => MyDialogWidget(
                            message: "Log Out?",
                            header: "Login",
                            but1Text: "OK",
                            but2Text: "Cancel"))
                        )
                     : UserDataService().logout();
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
    //UserData _userData = Provider.of<UserData>(context, listen: false);
    UserData? _userData = UserDataService().userdata;

    return Scaffold(
      backgroundColor: APP_BACKGROUND_COLOR,
      appBar: AppBar(
        title: MyAppbarTitle('Profile'),
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.only(left: 20, right: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[

            // Header
            buildLoginHeader(),

            Container(

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  SizedBox(height: 20),

                  // Display Name
                  MyTextFormField(
                    backgroundColor: APP_BACKGROUND_COLOR,
                    foregroundColor: Colors.white,
                    controller: _displaynameControl,
                    hintText: "Type display name here",
                    labelText: "Display Name",
                    onFieldSubmitted: (value){
                      UserDataService().updateFields({
                        "displayName":value
                      });
                    },
                  ),

                  SizedBox(height: 20),

                  // Email
                  MyTextFormField(
                    backgroundColor: APP_BACKGROUND_COLOR,
                    foregroundColor: Colors.white,
                    controller: _emailController,
                    hintText: "No email address",
                    labelText: "Email",
                    isPasswordField: false,
                    isReadOnly: true,
                  ),

                  SizedBox(height: 20),

                ],
              ),
            )
          ],
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
