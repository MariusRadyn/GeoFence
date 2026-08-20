import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/home_page.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => SignupPageState();
}

class SignupPageState extends State<SignupPage> {
  final FirebaseAuthService _auth = FirebaseAuthService();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _pw2Controller = TextEditingController();
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _userController.dispose();
    _emailController.dispose();
    _pwController.dispose();
    _pw2Controller.dispose();

    super.dispose();
  }

  Future<void> _openTerms() async {
    final uri = Uri.parse(termsAndConditionsUrl);
    final opened = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      MyGlobalMessage.show(
        'Terms and Conditions',
        'Could not open the link.',
        MyMessageType.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    UserData? userData = context.read<UserDataService>().userdata;

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
              MyTextFormField(
                controller: _emailController,
                hintText: "Enter Email Address",
              ),

              SizedBox(height: 20),

              MyTextFormField(
                controller: _pwController,
                hintText: "Password",
                isPasswordField: true,
              ),

              SizedBox(height: 20),

              MyTextFormField(
                controller: _pw2Controller,
                hintText: "Confirm Password",
                isPasswordField: true,
              ),

              SizedBox(height: 12),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acceptedTerms,
                    activeColor: colorOrange,
                    onChanged: (v) =>
                        setState(() => _acceptedTerms = v == true),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('I have read and accept the '),
                          GestureDetector(
                            onTap: _openTerms,
                            child: const Text(
                              'Terms and Conditions',
                              style: TextStyle(
                                color: colorOrange,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const Text('.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.only(
                        left: 80, right: 80, top: 10, bottom: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      color: colorOrange,
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
                              if (!_acceptedTerms) {
                                MyGlobalMessage.show(
                                  'Terms required',
                                  'Please accept the Terms and Conditions to create an account.',
                                  MyMessageType.info,
                                );
                                return;
                              }
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

    AuthResult? result =
        await _auth.fireAuthCreateUserWithEmail(context, email, password);

    if (result.user != null) {
      userData?.userID = result.user!.uid;
      userData?.displayName = username;

      printDebugMsg('User created successfully');

      if (!mounted) return;
      await context.read<UserDataService>().create(
            UserData(
              displayName: username,
              email: email,
              emailValidated: result.user!.emailVerified,
              termsAccepted: true,
              termsVersion: termsAndConditionsVersion,
            ),
            uid: result.user!.uid,
          );
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(),
        ),
      );
    } else {
      printDebugMsg('Error creating user');
    }
  }
}
