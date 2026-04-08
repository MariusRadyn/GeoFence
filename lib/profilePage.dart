import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'editProfilePicPage.dart';
import 'firebase.dart';
import 'homePage.dart';

class profilePage extends StatefulWidget {
  const profilePage({super.key});

  @override
  State<profilePage> createState() => _profilePageState();
}

class _profilePageState extends State<profilePage> {
  final TextEditingController _displaynameControl = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _Control = TextEditingController();
  final TextEditingController _pwControl = TextEditingController();

  @override
  void initState() {
    super.initState();
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
                      MyTextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        text:  "No",
                      ),

                      const SizedBox(width: 20),

                      // OK Button
                      MyTextButton(
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
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
                      child: CircleAvatar(
                        backgroundImage:  user.userdata?.imageURL != null &&  user.userdata!.imageURL!.isNotEmpty
                            ? CachedNetworkImageProvider(user.userdata!.imageURL!) as ImageProvider
                            : AssetImage(IMAGE_PROFILE),
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

          // Logout Button
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
                buildLoginHeader(user),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        SizedBox(height: 20),

                        // Display Name
                        MyTextFormField(
                          backgroundColor: APP_BACKGROUND_COLOR,
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
                          backgroundColor: APP_BACKGROUND_COLOR,
                          foregroundColor: Colors.white,
                          controller: _emailController,
                          hintText: "Enter Email",
                          labelText: "Email",
                          isPasswordField: false,
                          isReadOnly: true,
                        ),

                        SizedBox(height: 20),

                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      }
    );
  }
}
