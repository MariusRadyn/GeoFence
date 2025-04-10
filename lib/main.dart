import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geofence/homePage.dart';
import 'package:geofence/utils.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Web app
    if(kIsWeb){
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      print("Web App");
    }else print("Android App");

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => UserData()),
        ],
        child: MyApp(),
      ),
    );

  }
  catch(e){
    print('Error $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: COLOR_BLACK_LIGHT,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.blueGrey,
      ),
      home: HomePage(),
    );
  }
}

