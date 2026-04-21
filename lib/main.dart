
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geofence/splashScreen.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/firebase_options.dart';
import 'package:provider/provider.dart';
import 'MqttService.dart';
import 'gpsServices.dart';
import 'mqtt_lifecycle_handler.dart';
late AppLifecycleHandler lifecycleHandler;

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

     await Firebase.initializeApp(
       options: DefaultFirebaseOptions.currentPlatform,
     );

    await initializeGpsService();

    final mqttService = MqttService();
    lifecycleHandler = AppLifecycleHandler(mqttService);
    lifecycleHandler.init();

    // Web app
    //if(kIsWeb){
    //  await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    //  print("Web App");
    //}else print("Android App");

    //runApp(MyApp());

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => SettingsService()..load()),
          ChangeNotifierProvider(create: (_) => UserDataService()..load()),
          ChangeNotifierProvider(create: (_) => MonitorSettingsService()..load()),
          ChangeNotifierProvider(create: (_) => BaseStationService()..load()),
          ChangeNotifierProvider(create: (_) => OperatorService()..load()),
        ],
        child: MyApp(),
      ),
    );
  }
  catch(e){
    printMsg('StartUp Error: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: Colors.blueGrey,
        ),
        home: SplashScreen(),
    );
  }
}