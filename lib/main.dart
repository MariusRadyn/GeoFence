import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:geofence/app_flavor.dart';
import 'package:geofence/home_page.dart';
import 'package:geofence/splash_screen.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/firebase_options.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/shop_page.dart';
import 'package:provider/provider.dart';
import 'mqtt_service.dart';
import 'gps_services.dart';
import 'mqtt_lifecycle_handler.dart';

AppLifecycleHandler? lifecycleHandler;

/// reCAPTCHA v3 site key from Firebase Console → App Check → Web app.
/// Pass with: `--dart-define=RECAPTCHA_V3_SITE_KEY=your_key`
const String _recaptchaV3SiteKey = String.fromEnvironment(
  'RECAPTCHA_V3_SITE_KEY',
);

Future<void> _activateAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
      providerWeb: kDebugMode || _recaptchaV3SiteKey.isEmpty
          ? WebDebugProvider()
          : ReCaptchaV3Provider(_recaptchaV3SiteKey),
    );

    // Helps surface token issues early in logs.
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    if (kDebugMode) {
      printDebugMsg(
        'App Check activated (debug). '
        'Register the debug token printed in the console under '
        'Firebase Console → App Check → Manage debug tokens.',
      );
      if (kIsWeb && _recaptchaV3SiteKey.isEmpty) {
        printDebugMsg(
          'Web release needs --dart-define=RECAPTCHA_V3_SITE_KEY=...',
        );
      }
    }
  } catch (e) {
    printDebugMsg('App Check activate failed: $e');
  }
}

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    if (kIsWeb) {
      usePathUrlStrategy();
      cacheLaunchRoute();
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await _activateAppCheck();

    // Keep auth across browser refreshes (web only).
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }

    await initializeGoogleSignIn();

    if (AppConfig.enableFieldServices) {
      await initializeGpsService();

      final mqttService = MqttService();
      lifecycleHandler = AppLifecycleHandler(mqttService);
      lifecycleHandler!.init();
    }

    printDebugMsg('Starting flavor: ${AppConfig.flavor.name}');

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService()..load()),
          ChangeNotifierProvider(create: (_) => UserDataService()..load()),
          ChangeNotifierProvider(create: (_) => MonitorSettingsService()..load()),
          ChangeNotifierProvider(create: (_) => BaseStationService()..load()),
          ChangeNotifierProvider(create: (_) => OperatorService()),
          ChangeNotifierProvider(create: (_) => ShopCartService()),
          ChangeNotifierProvider(create: (_) => ShopCatalogService()),
        ],
        child: const MyApp(),
      ),
    );
  } catch (e) {
    printDebugMsg('StartUp Error: $e');
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
      title: AppConfig.appTitle,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.blueGrey,
      ),
      home: launchOpensProfile
          ? const HomePage(openProfileOnLaunch: true)
          : const SplashScreen(),
    );
  }
}
