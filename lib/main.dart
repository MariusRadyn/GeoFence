import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, kProfileMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:geofence/app_flavor.dart';
import 'package:geofence/home_page.dart';
import 'package:geofence/splash_screen.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/firebase_options.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/shop_page.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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
    // Play Integrity only works for Play-distributed / properly attested builds.
    // Debug + profile (and APP_CHECK_DEBUG=true) use the debug provider so
    // local/sideload installs don't spam "App attestation failed" 403s.
    const forceDebugAppCheck = bool.fromEnvironment(
      'APP_CHECK_DEBUG',
      defaultValue: false,
    );
    final useDebugProvider =
        kDebugMode || kProfileMode || forceDebugAppCheck;

    // On production web, WebDebugProvider requires a registered debug token.
    // If no reCAPTCHA key is provided, skip App Check so Firestore/Auth can
    // still work for browser-installed PWAs.
    if (kIsWeb &&
        !kDebugMode &&
        !forceDebugAppCheck &&
        _recaptchaV3SiteKey.isEmpty) {
      printDebugMsg(
        'App Check skipped on web release (missing RECAPTCHA_V3_SITE_KEY).',
      );
      return;
    }

    await FirebaseAppCheck.instance.activate(
      providerAndroid: useDebugProvider
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: useDebugProvider
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
      providerWeb: kDebugMode ||
              forceDebugAppCheck ||
              _recaptchaV3SiteKey.isEmpty
          ? WebDebugProvider()
          : ReCaptchaV3Provider(_recaptchaV3SiteKey),
    );

    // Helps surface token issues early in logs.
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    if (useDebugProvider) {
      printDebugMsg(
        'App Check: debug provider active. '
        'Look in logcat for "Enter this debug secret" / debug token, then add it under '
        'Firebase Console → App Check → Apps → Manage debug tokens.',
      );
    }
    if (kIsWeb && _recaptchaV3SiteKey.isEmpty) {
      printDebugMsg(
        'Web release needs --dart-define=RECAPTCHA_V3_SITE_KEY=...',
      );
    }
  } catch (e) {
    printDebugMsg('App Check activate failed: $e');
  }
}

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Phone UI stays portrait — no landscape when the device is turned.
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

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
  static const _links = MethodChannel('limitless.iot.trinity/links');

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _links.setMethodCallHandler((call) async {
        if (call.method == 'onLink') {
          _handleDeepLink(call.arguments?.toString());
        }
        return null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final initial = await _links.invokeMethod<String>('getInitialLink');
          _handleDeepLink(initial);
        } catch (_) {}
      });
    }
  }

  void _handleDeepLink(String? link) {
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    final isShop = (uri.scheme == 'limitless' && uri.host == 'shop') ||
        uri.queryParameters['page'] == 'shop' ||
        uri.path == '/shop' ||
        uri.path == '/shop/';
    if (!isShop) return;
    // Close PayFast Custom Tab / in-app browser so the native shop is visible.
    try {
      closeInAppWebView();
    } catch (_) {}
    // Wait a beat so navigator/home exist after cold start.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      ShopPage.openInApp();
    });
  }

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
          : launchOpensShop
              ? const HomePage(openShopOnLaunch: true)
              : const SplashScreen(),
    );
  }
}
