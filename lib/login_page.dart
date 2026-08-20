import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _busyResetting = false;

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
      final code = error.code.name;
      final description = error.description ?? 'Google Sign-In failed';
      if (description.contains('[16]') ||
          description.toLowerCase().contains('reauth')) {
        return 'Play Store sign-in failed (certificate mismatch).\n'
            'Debug and Play use different keys. In Firebase, add the '
            'App signing SHA-1 from Play Console → Manage Play app signing '
            '(not the upload key). Also add SHA-256, download new '
            'google-services.json, rebuild, and reinstall from Play Store.';
      }
      if (code == 'canceled' && !description.contains('[16]')) {
        return 'Google Sign-In was canceled.';
      }
      return '$code: $description';
    }

    // General fallback
    return error.toString().replaceFirst("Exception: ", "");
  }

  void _signUpScreen (){
    double width = MediaQuery.of(context).size.width * 0.8;
    double height = MediaQuery.of(context).size.height * 0.72;
    bool acceptedTerms = false;

    // Keep email/password already typed on the login form (shared controllers).
    // Only reset the confirm-password field used by signup.
    _pwController2.text = "";

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: SizedBox(
                width: width > 500 ? 500 : width,
                height: height > 680 ? 680 : height,
                child: Container(
                  decoration: BoxDecoration(
                      gradient: myTileGradient(),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.blue,
                          width: 2
                      )
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [

                        const MyText(
                          text: "Sign Up",
                          fontsize: 20,
                        ),

                        SizedBox(height: 10),

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

                        Padding(
                          padding: EdgeInsets.only(left: 20, right: 20),
                          child: MyTextFormField(
                            controller: _emailController,
                            inputType: TextInputType.emailAddress,
                            hintText: "Enter Email Address",
                            backgroundColor: colorAppBackground,
                            foregroundColor: Colors.white,
                          ),
                        ),

                        SizedBox(height: 20),

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

                        SizedBox(height: 12),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: acceptedTerms,
                                activeColor: colorOrange,
                                side: const BorderSide(color: Colors.white54),
                                onChanged: (v) {
                                  setDialogState(() {
                                    acceptedTerms = v == true;
                                  });
                                },
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      const Text(
                                        'I have read and accept the ',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: _openTermsAndConditions,
                                        child: const Text(
                                          'Terms and Conditions',
                                          style: TextStyle(
                                            color: colorOrange,
                                            fontSize: 13,
                                            decoration: TextDecoration.underline,
                                            decorationColor: colorOrange,
                                          ),
                                        ),
                                      ),
                                      const Text(
                                        '.',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            myTextButton(
                              text: 'Cancel',
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                            ),

                            SizedBox(width: 10),

                            myTextButton(
                              text:'OK',
                              onPressed: () async {
                                if (!acceptedTerms) {
                                  MyGlobalMessage.show(
                                    'Terms required',
                                    'Please accept the Terms and Conditions to create an account.',
                                    MyMessageType.info,
                                  );
                                  return;
                                }

                                final user = await _signUp(
                                  acceptedTerms: acceptedTerms,
                                );

                                if (user != null) {
                                  if(!mounted) return;
                                  // ignore: use_build_context_synchronously
                                  Navigator.of(context).pop();
                                  if(!mounted) return;
                                  // ignore: use_build_context_synchronously
                                  _showEmailVerificationDialog(context);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openTermsAndConditions() async {
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

  /// Dialog for first-time Google sign-in (new account).
  Future<bool> _promptAcceptTerms() async {
    bool accepted = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: colorAppBackground,
              title: const MyText(
                text: 'Terms and Conditions',
                fontsize: 18,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MyText(
                    text:
                        'To create a Limitless IOT account you must accept our Terms and Conditions.',
                    color: Colors.white70,
                    fontsize: 14,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _openTermsAndConditions,
                    child: const Text(
                      'Read Terms and Conditions',
                      style: TextStyle(
                        color: colorOrange,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: accepted,
                    activeColor: colorOrange,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const MyText(
                      text: 'I accept the Terms and Conditions',
                      color: Colors.white70,
                      fontsize: 13,
                    ),
                    onChanged: (v) =>
                        setDialogState(() => accepted = v == true),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const MyText(text: 'Cancel', color: Colors.white70),
                ),
                TextButton(
                  onPressed: accepted ? () => Navigator.pop(ctx, true) : null,
                  child: MyText(
                    text: 'Continue',
                    color: accepted ? colorOrange : Colors.grey,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    return result == true;
  }

  Future<User?> _signUp({bool acceptedTerms = false}) async {
    UserDataService userService = context.read<UserDataService>();
    AuthResult result = AuthResult();

    if (!acceptedTerms) {
      MyGlobalMessage.show(
        'Terms required',
        'Please accept the Terms and Conditions to create an account.',
        MyMessageType.info,
      );
      return null;
    }
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
          await userService.create(
              UserData(
                displayName: _userController.text,
                email: _emailController.text,
                emailValidated: result.user!.emailVerified,
                termsAccepted: true,
                termsVersion: termsAndConditionsVersion,
              ),
              uid: result.user!.uid
          );

          printDebugMsg('User Created');
        } else {
          await userService.load();
        }

        await context.read<SettingsService>().load();

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
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      MyGlobalMessage.show("Info", 'Please enter email address.', MyMessageType.info);
      return false;
    }
    if (!email.contains('@')) {
      MyGlobalMessage.show("Info", 'Please enter a valid email address.', MyMessageType.info);
      return false;
    }

    try {
      if (await firebaseAuthService.fireAuthResetPassword(context, email)) {
        if (userService.userdata != null) {
          userService.isUserLoggedIn = false;
        }
        printDebugMsg('Password Reset email requested for $email');
        return true;
      }
      // fireAuthResetPassword already showed the Firebase error
      return false;
    } catch (e) {
      MyGlobalMessage.show("Error", '$e', MyMessageType.error);
      return false;
    }
  }

  Future<void> _onResetPasswordTap() async {
    if (busyLoggingIn || _busyResetting) return;

    FocusScope.of(context).unfocus();
    setState(() => _busyResetting = true);
    MyGlobalSnackBar.show('Sending password reset…');

    try {
      final ok = await _resetPasswordWithEmail();
      if (!mounted) return;
      if (ok) {
        MyGlobalMessage.show(
          "Check email",
          "We sent a reset link.\n\n"
          "Check spam/junk.\n"
          "If you only ever used Google Sign-In, there is no password to reset — use Google.",
          MyMessageType.info,
        );
      }
    } finally {
      if (mounted) setState(() => _busyResetting = false);
    }
  }
  Future<bool> _sendValidateEmail() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return false;
    if (user.emailVerified) return true;

    try {
      await user.sendEmailVerification();
      MyGlobalMessage.show(
        'Email sent',
        'Check your inbox for the verification link.',
        MyMessageType.info,
      );
      return true;
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'too-many-requests' =>
          'Too many attempts. Wait a few minutes before resending.',
        'network-request-failed' => 'Network error. Check your connection.',
        _ => e.message ?? e.code,
      };
      MyGlobalMessage.show('Verification email', msg, MyMessageType.error);
      return false;
    } catch (e) {
      debugPrint('sendEmailVerification: $e');
      MyGlobalMessage.show(
        'Verification email',
        'Could not send verification email. Try again later.',
        MyMessageType.error,
      );
      return false;
    }
  }
  void _showEmailVerificationDialog(BuildContext context) {
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,

      builder: (dialogContext) {
        timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
          final user = FirebaseAuth.instance.currentUser;

          if (user == null) {
            timer.cancel();
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
            return;
          }

          try {
            await user.reload();
          } catch (_) {
            return;
          }

          if (!dialogContext.mounted) return;

          final verified =
              FirebaseAuth.instance.currentUser?.emailVerified ?? false;
          if (verified) {
            timer.cancel();
            Navigator.of(dialogContext).pop();
            final appContext = navigatorKey.currentContext;
            if (appContext != null) {
              await appContext.read<UserDataService>().load();
            }
            MyGlobalMessage.show(
              'Email verified',
              'Your email address has been verified.',
              MyMessageType.info,
            );
          }
        });

        return AlertDialog(
          title: const MyText(text:"Email Verification",fontsize: 20),
          content: const MyText(
            text:"Please click the verification link sent to your email.\n"
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
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
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

      if (!result.isSuccess || result.user == null) {
        if (userService.userdata != null) {
          userService.isUserLoggedIn = false;
        }
        if (result.code != null) {
          MyGlobalMessage.show("Login", result.code!, MyMessageType.warning);
        } else if (result.exception != null) {
          MyGlobalMessage.show("Login", result.exception.toString(), MyMessageType.warning);
        }
        return false;
      }

      final authUser = result.user!;
      await userService.load();

      if (userService.userdata == null) {
        final email = authUser.email ?? _emailController.text.trim();
        final displayName = authUser.displayName?.trim().isNotEmpty == true
            ? authUser.displayName!.trim()
            : (email.contains('@') ? email.split('@').first : email);

        await userService.create(
          UserData(
            displayName: displayName,
            email: email,
            emailValidated: authUser.emailVerified,
          ),
          uid: authUser.uid,
        );
        await userService.load();
      }

      await _reloadUserScopedData();

      if (userService.userdata == null) {
        MyGlobalMessage.show(
          'Login',
          'Signed in, but your profile could not be loaded.\n'
          'Check your connection and try again.',
          MyMessageType.warning,
        );
        await FirebaseAuth.instance.signOut();
        return false;
      }

      userService.isUserLoggedIn = true;

      try {
        await authUser.reload();
      } catch (_) {}

      final verified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (!verified) {
        MyGlobalMessage.show(
          'Verify Email',
          'Your email is not verified yet.\n'
          'Please open your email and click the verify link.',
          MyMessageType.warning,
        );
      }

      return true;
    } catch (e) {
      MyGlobalMessage.show("Login", '$e', MyMessageType.error);
      return false;
    } finally {
      if (mounted) {
        setState(() {
          busyLoggingIn = false;
        });
      }
    }
  }
  Future<void> _reloadUserScopedData() async {
    if (!mounted) return;
    await Future.wait([
      context.read<SettingsService>().load(),
      context.read<BaseStationService>().load(),
      context.read<MonitorSettingsService>().load(),
      context.read<OperatorService>().load(),
    ]);
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

      if (!result.isSuccess || result.user == null) {
        final err = _getGoogleError(result.exception);
        MyGlobalMessage.show("Error", err, MyMessageType.error);
        return false;
      }

      final authUser = result.user!;
      printDebugMsg('Google login UID: ${authUser.uid} email: ${authUser.email}');
      await userService.load();

      if (userService.userdata == null) {
        final doc = await FirebaseFirestore.instance
            .collection(collectionUsers)
            .doc(authUser.uid)
            .get();

        if (!doc.exists) {
          final accepted = await _promptAcceptTerms();
          if (!accepted) {
            await FirebaseAuth.instance.signOut();
            MyGlobalMessage.show(
              'Terms required',
              'You must accept the Terms and Conditions to create an account.',
              MyMessageType.info,
            );
            return false;
          }

          await userService.create(
            UserData(
              displayName: authUser.displayName ?? "",
              email: authUser.email ?? "",
              emailValidated: true,
              imageURL: authUser.photoURL ?? "",
              termsAccepted: true,
              termsVersion: termsAndConditionsVersion,
            ),
            uid: authUser.uid,
          );
          await userService.load();
        }
      }

      await _reloadUserScopedData();

      if (userService.userdata == null) {
        MyGlobalMessage.show(
          'Login',
          'Signed in with Google, but your profile could not be loaded.\n'
          'Check your connection and try again.',
          MyMessageType.warning,
        );
        await FirebaseAuth.instance.signOut();
        return false;
      }

      userService.isUserLoggedIn = true;
      return true;
    } catch (e) {
      MyGlobalMessage.show("Error(LoginWithGoogle)", '$e', MyMessageType.debug);
      return false;
    } finally {
      if (mounted) {
        setState(() {
          busyLoggingIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: MyText(
          text: "Login",
          fontsize: 20,
        ),
      ),
      body: homeBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
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

                    const SizedBox(width: 4),

                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: (busyLoggingIn || _busyResetting)
                            ? null
                            : _onResetPasswordTap,
                        borderRadius: BorderRadius.circular(6),
                        splashColor: colorOrange.withValues(alpha: 0.25),
                        highlightColor: colorOrange.withValues(alpha: 0.12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: _busyResetting
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colorOrange,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Sending…',
                                      style: TextStyle(
                                        color: colorOrange.withValues(
                                          alpha: 0.85,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : const Text(
                                  'Reset',
                                  style: TextStyle(
                                    color: colorOrange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
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
                      onTap: busyLoggingIn ? null : () {
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
                      onPressed: busyLoggingIn
                          ? () {}
                          : () async {
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
                      onPressed: busyLoggingIn
                          ? () {}
                          : () {
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
                      onPressed: busyLoggingIn
                          ? null
                          : () {
                        Navigator.of(context).pop();
                      },
                    ),

                    const SizedBox(width: 10),

                    // OK Button
                    myTextButton(
                      text: 'OK',
                      onPressed: busyLoggingIn
                          ? null
                          : () async {
                        final loggedIn = await _loginWithEmail();
                        if (!mounted || !loggedIn) return;

                        final needsVerify = !(FirebaseAuth
                                .instance.currentUser?.emailVerified ??
                            false);
                        Navigator.of(context).pop();

                        if (needsVerify) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final rootContext = navigatorKey.currentContext;
                            if (rootContext != null) {
                              _showEmailVerificationDialog(rootContext);
                            }
                          });
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
            if (busyLoggingIn)
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
                          const SizedBox(height: 16),
                          const MyText(
                            text: "Logging in...",
                            color: Colors.white,
                            fontsize: 16,
                          ),
                          const SizedBox(height: 8),
                          const MyText(
                            text: "Please wait while we set up your account.",
                            color: Colors.grey,
                            fontsize: 13,
                          ),
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
}
