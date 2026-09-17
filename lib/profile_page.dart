import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/account_deletion_service.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'edit_profile_pic_page.dart';
//import 'firebase.dart';
import 'home_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  final TextEditingController _displaynameControl = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  //final TextEditingController _Control = TextEditingController();
  //final TextEditingController _pwControl = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(privacyPolicyUrl);
    final opened = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      MyGlobalMessage.show(
        'Privacy policy',
        'Could not open the privacy policy link.',
        MyMessageType.warning,
      );
    }
  }

  void _showDeleteDataDialog(BuildContext context) {
    final passwordController = TextEditingController();
    final authUser = FirebaseAuth.instance.currentUser;
    final usesEmailPassword = authUser?.providerData.any(
          (p) => p.providerId == EmailAuthProvider.PROVIDER_ID,
        ) ??
        false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var confirmed = false;
        var busy = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> runDelete() async {
              if (!confirmed || busy) return;

              setDialogState(() => busy = true);
              try {
                await AccountDeletionService.deleteCurrentUserDataOnly(
                  password: usesEmailPassword
                      ? passwordController.text
                      : null,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!context.mounted) return;

                await context.read<UserDataService>().load();
                if (!context.mounted) return;
                
                await context.read<SettingsService>().load();
                if (!context.mounted) return;
                
                MyGlobalMessage.show(
                  'Data deleted',
                  'Your app data has been removed. Your account is still active.',
                  MyMessageType.info,
                );
              } on FirebaseAuthException catch (e) {
                setDialogState(() => busy = false);
                final msg = switch (e.code) {
                  'missing-password' =>
                    'Enter your password to confirm data deletion.',
                  'wrong-password' => 'Incorrect password.',
                  'requires-recent-login' =>
                    'Sign out, sign in again, then retry.',
                  _ => e.message ?? e.code,
                };
                MyGlobalMessage.show('Delete failed', msg, MyMessageType.error);
              } catch (e) {
                setDialogState(() => busy = false);
                MyGlobalMessage.show(
                  'Delete failed',
                  '$e',
                  MyMessageType.error,
                );
              }
            }

            return AlertDialog(
              backgroundColor: colorAppTitle,
              title: const MyText(
                text: 'Delete my data?',
                color: Colors.white,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MyText(
                      text:
                          'This permanently deletes your GeoFence zones, '
                          'tracking history, IoT data, operators, shop orders, '
                          'and profile photo. Your account and sign-in stay active.',
                      color: Colors.white70,
                      fontsize: 14,
                    ),
                    const SizedBox(height: 12),
                    if (usesEmailPassword) ...[
                      MyTextFormField(
                        controller: passwordController,
                        labelText: 'Password',
                        isPasswordField: true,
                        backgroundColor: colorAppBar,
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(height: 8),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: confirmed,
                      activeColor: colorOrange,
                      title: const MyText(
                        text: 'I understand this cannot be undone',
                        color: Colors.white70,
                        fontsize: 13,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: busy
                          ? null
                          : (v) => setDialogState(() => confirmed = v == true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const MyText(text: 'Cancel', color: Colors.white70),
                ),
                TextButton(
                  onPressed: busy || !confirmed ? null : runDelete,
                  child: MyText(
                    text: busy ? 'Deleting…' : 'Delete data',
                    color: busy || !confirmed ? Colors.grey : Colors.redAccent,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final passwordController = TextEditingController();
    final authUser = FirebaseAuth.instance.currentUser;
    final usesEmailPassword = authUser?.providerData.any(
          (p) => p.providerId == EmailAuthProvider.PROVIDER_ID,
        ) ??
        false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var confirmed = false;
        var busy = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> runDelete() async {
              if (!confirmed || busy) return;

              setDialogState(() => busy = true);
              try {
                await AccountDeletionService.deleteCurrentUserAccount(
                  password: usesEmailPassword
                      ? passwordController.text
                      : null,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!context.mounted) return;
                await context.read<UserDataService>().logout();
                if (!context.mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
                MyGlobalMessage.show(
                  'Account deleted',
                  'Your account and app data have been removed.',
                  MyMessageType.info,
                );
              } on FirebaseAuthException catch (e) {
                setDialogState(() => busy = false);
                final msg = switch (e.code) {
                  'missing-password' =>
                    'Enter your password to confirm deletion.',
                  'wrong-password' => 'Incorrect password.',
                  'requires-recent-login' =>
                    'Sign out, sign in again, then retry deletion.',
                  _ => e.message ?? e.code,
                };
                MyGlobalMessage.show('Delete failed', msg, MyMessageType.error);
              } catch (e) {
                setDialogState(() => busy = false);
                MyGlobalMessage.show(
                  'Delete failed',
                  '$e',
                  MyMessageType.error,
                );
              }
            }

            return AlertDialog(
              backgroundColor: colorAppTitle,
              title: const MyText(
                text: 'Delete account?',
                color: Colors.white,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MyText(
                      text:
                          'This permanently deletes your account, profile, '
                          'GeoFence zones, tracking history, IoT data, '
                          'operators, and shop orders.',
                      color: Colors.white70,
                      fontsize: 14,
                    ),
                    const SizedBox(height: 12),
                    if (usesEmailPassword) ...[
                      MyTextFormField(
                        controller: passwordController,
                        labelText: 'Password',
                        isPasswordField: true,
                        backgroundColor: colorAppBar,
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(height: 8),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: confirmed,
                      activeColor: colorOrange,
                      title: const MyText(
                        text: 'I understand this cannot be undone',
                        color: Colors.white70,
                        fontsize: 13,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: busy
                          ? null
                          : (v) => setDialogState(() => confirmed = v == true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const MyText(text: 'Cancel', color: Colors.white70),
                ),
                TextButton(
                  onPressed: busy || !confirmed ? null : runDelete,
                  child: MyText(
                    text: busy ? 'Deleting…' : 'Delete',
                    color: busy || !confirmed ? Colors.grey : Colors.redAccent,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void showLogoutDialog (BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                  gradient: myTileGradient(),
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
                    text:  "Log Out",
                    fontsize: 20,
                  ),

                  const SizedBox(height: 10),

                  // Message
                  const MyText(
                    text:  "Are you sure?",
                    fontsize: 18,
                    color: Colors.grey,
                  ),

                  const SizedBox(height: 20),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // No Button
                      myTextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        text:  "No",
                      ),

                      const SizedBox(width: 20),

                      // OK Button
                      myTextButton(
                        onPressed: () async {
                          await context.read<UserDataService>().logout();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                        text: 'Yes',
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildLoginHeader(UserDataService user) {
    _emailController.text = user.userdata!.email ?? "";
    _displaynameControl.text = user.userdata!.displayName;

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
                colors: [colorBlue, colorIceBlue],
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
                    onTap: () async {
                      final (ProfilePicData? profilePic) = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditProfilePicPage(
                            docId: user.userdata!.userID,
                            imageURL: user.userdata!.imageURL,
                            imageFilename: user.userdata!.imageFilename,
                            profileType: profileTypeUser,
                          ),
                        ),
                      );
                      if(profilePic?.imageURL != null && profilePic!.update){
                        setState(() {
                          user.userdata!.imageURL = profilePic.imageURL;
                          user.userdata!.imageFilename = profilePic.imageFilename;
                        });
                        context.read<UserDataService>().save(user.userdata!);
                      }
                    },
                    child: CircleAvatar(
                      radius: 55,
                      backgroundColor: Colors.white,
                      child: kIsWeb
                          ? NetworkCircleAvatar(
                              imageUrl: user.userdata?.imageURL,
                              radius: 50,
                              backgroundColor: Colors.grey.shade300,
                            )
                          : CircleAvatar(
                              backgroundImage: user.userdata?.imageURL != null &&
                                      user.userdata!.imageURL!.isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      user.userdata!.imageURL!,
                                    ) as ImageProvider
                                  : const AssetImage(iconProfile)
                                      as ImageProvider,
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
              child: showWelcomeMsg(context),
            ),
          ),

          // Logout Button
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 180),
              width: 120,
              height: 40,
              decoration: const BoxDecoration(
                color: colorOrange,
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: TextButton(
                child: Text('Log Out',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                onPressed: () {
                  showLogoutDialog(context);
                  //user.userdata!.isLoggedIn
                  //? showLogoutDialog(context)
                  //    : user.logout();
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

    return Consumer<UserDataService>(
      builder: (_, user,__) {

        // Logged out - Back to Home
        if (user.userdata == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HomePage(),
              ),
            );
          });

          return const SizedBox(); // temporary widget
        }

        return Scaffold(
          backgroundColor: colorAppBackground,
          appBar: AppBar(
            title: myAppbarTitle('Profile'),
            backgroundColor: colorAppBar,
            foregroundColor: Colors.white,
          ),
          body: Padding(
            padding: EdgeInsets.only(left: 20, right: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[

                // Header
                buildLoginHeader(user),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        SizedBox(height: 20),

                        // Display Name
                        MyTextFormField(
                          backgroundColor: colorAppBackground,
                          foregroundColor: Colors.white,
                          controller: _displaynameControl,
                          hintText: "Enter Name",
                          labelText: "Display Name",
                          onFieldSubmitted: (value) {
                            user.updateFields({
                              "displayName": value
                            });
                          },
                        ),

                        SizedBox(height: 20),

                        // Email
                        MyTextFormField(
                          backgroundColor: colorAppBackground,
                          foregroundColor: Colors.white,
                          controller: _emailController,
                          hintText: "Enter Email",
                          labelText: "Email",
                          isPasswordField: false,
                          isReadOnly: true,
                        ),

                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const MyText(
                            text: 'Delete my data',
                            color: Colors.orangeAccent,
                            fontsize: 16,
                          ),
                          subtitle: const MyText(
                            text:
                                'Remove app data but keep your account',
                            color: Colors.white54,
                            fontsize: 12,
                          ),
                          onTap: () => _showDeleteDataDialog(context),
                        ),

                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const MyText(
                            text: 'Delete account & data',
                            color: Colors.redAccent,
                            fontsize: 16,
                          ),
                          subtitle: const MyText(
                            text:
                                'Permanently delete your account and app data',
                            color: Colors.white54,
                            fontsize: 12,
                          ),
                          onTap: () => _showDeleteAccountDialog(context),
                        ),

                        SizedBox(height: 20),

                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: _openPrivacyPolicy,
                    child: const MyText(
                      text: 'Privacy policy',
                      color: Colors.white38,
                      fontsize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}
