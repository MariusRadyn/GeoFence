import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geofence/utils.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart' as perm;

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<Position> determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  // Test if location services are enabled.
  writeLog('Check Location services ... ');
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (serviceEnabled == false) {
    // Location services are not enabled don't continue
    // accessing the position and request users of the
    // App to enable the location services.
    writeLog('Disabled.');

    return Future.error('Location services are disabled.');
  }
  writeLog('Enabled.');

  writeLog('Check Permission ...');
  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    writeLog('Denied');

    writeLog('Request Permission ... ');
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      writeLog('Denied');
      // Permissions are denied, next time you could try
      // requesting permissions again (this is also where
      // Android's shouldShowRequestPermissionRationale
      // returned true. According to Android guidelines
      // your App should show an explanatory UI now.
      return Future.error('Location permissions are denied');
    }
  }
  writeLog('Granted');

  if (permission == LocationPermission.deniedForever) {
    // Permissions are denied forever, handle appropriately.
    writeLog('Denied Forever');

    return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.');
  }

  final LocationSettings locationSettings = getLocationSettings();

  return await Geolocator.getCurrentPosition(
      locationSettings: locationSettings);
}
StreamSubscription<Position> startLocationStream() {
  final LocationSettings locationSettings = getLocationSettings();

  StreamSubscription<Position> positionStream =
      Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen((Position? position) {
    //print(position == null ? 'Unknown' : '${position.latitude.toString()}, ${position.longitude.toString()}');
  });

  return positionStream;
}
LocationSettings getLocationSettings() {
  LocationSettings locationsettings;

  if (defaultTargetPlatform == TargetPlatform.android) {
    locationsettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 10),
        //(Optional) Set foreground notification config to keep the app alive
        //when going to the background
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText:
              "Example app will continue to receive your location even when you aren't using it",
          notificationTitle: "Running in Background",
          enableWakeLock: true,
        ));
  } else if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    locationsettings = AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.fitness,
      distanceFilter: 100,
      pauseLocationUpdatesAutomatically: true,
      // Only set to true if our app will be started up in the background.
      showBackgroundLocationIndicator: false,
    );
  } else if (kIsWeb) {
    locationsettings = WebSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100,
      maximumAge: Duration(minutes: 5),
    );
  } else {
    locationsettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100,
    );
  }

  return locationsettings;
}
Future<void>  getPolylinePoints(double _originLatitude, double _originLongitude, double _destLatitude, double _destLongitude) async {
  PolylinePoints polylinePoints = PolylinePoints();
  PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
    googleApiKey: googleAPiKey,
    request: PolylineRequest(
      origin: PointLatLng(_originLatitude, _originLongitude),
      destination: PointLatLng(_destLatitude, _destLongitude),
      mode: TravelMode.driving,
      wayPoints: [PolylineWayPoint(location: "Sabo, Yaba Lagos Nigeria")],
    ),
  );
  print(result.points);
}


// Initialize the background service
Future<void> initializeGpsService() async {
  // final service = FlutterBackgroundService();
  //
  // // For Android, we need to create a notification channel
  // await service.configure(
  //   androidConfiguration: AndroidConfiguration(
  //     onStart: onStart,
  //     autoStart: false,
  //     isForegroundMode: true,
  //     notificationChannelId: 'location_tracking_channel',
  //     initialNotificationTitle: 'Location Tracking',
  //     initialNotificationContent: 'Tracking your location',
  //     foregroundServiceNotificationId: 888,
  //   ),
  //   iosConfiguration: IosConfiguration(
  //     autoStart: false,
  //     onForeground: onStart,
  //     onBackground: onIosBackground,
  //   ),
  //);
}


// Main background service function
// @pragma('vm:entry-point')
// void onStart(ServiceInstance service) async {
//   DartPluginRegistrant.ensureInitialized();
//
//    int _distanceFilter = SettingsService().settings!.logPointPerMeter;
//    bool _isVoicePromptOn = SettingsService().settings!.isVoicePromptOn;
//
//   // For Android, this needs to run in foreground with a persistent notification
//   if (service is AndroidServiceInstance) {
//     service.setAsForegroundService();
//   }
//
//   // Initialize location services
//   final location = loc.Location();
//
//   // Configure high accuracy
//   await location.changeSettings(
//     accuracy: loc.LocationAccuracy.high,
//     interval: 5000, // Update interval in milliseconds
//     distanceFilter: _distanceFilter as double, // Minimum distance in meters to trigger updates
//   );
//
//   // Request permissions if not already granted
//   bool serviceEnabled = await location.serviceEnabled();
//   if (!serviceEnabled) {
//     serviceEnabled = await location.requestService();
//     if (!serviceEnabled) {
//       return;
//     }
//   }
//
//   loc.PermissionStatus permissionStatus = await location.hasPermission();
//   if (permissionStatus == loc.PermissionStatus.denied) {
//     permissionStatus = await location.requestPermission();
//     if (permissionStatus != loc.PermissionStatus.granted) {
//       return;
//     }
//   }
//
//   // Listen for location updates
//   location.onLocationChanged.listen((loc.LocationData currentLocation) {
//     // Here you can:
//     // 1. Send location data to your server
//     // 2. Update local storage
//     // 3. Update service notification with current location
//
//     // Example: Update the notification with new coordinates
//     if (service is AndroidServiceInstance) {
//       service.setForegroundNotificationInfo(
//         title: "Tracking Location",
//         content: "Lat: ${currentLocation.latitude}, Lng: ${currentLocation.longitude}",
//       );
//     }
//
//     // Send data to your app if it's running
//     service.invoke('locationUpdate', {
//       'latitude': currentLocation.latitude,
//       'longitude': currentLocation.longitude,
//       'timestamp': DateTime.now().toString(),
//     });
//   });
// }

class LocationService {
  static Future<void> requestPermissions() async {
    // Request location permissions
    await perm.Permission.locationAlways.request();
    await perm.Permission.notification.request();
  }
  Future<void> startLocationTracking() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        initialNotificationTitle: 'Background Service',
        initialNotificationContent: 'Running in the background...',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        //onBackground: onIosBackground,
      ),
    );

    await service.startService();
  }
  static Future<void> stopLocationTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  void onStart(ServiceInstance service) async {
    // Initialize FlutterLocalNotificationsPlugin
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

    if (service is AndroidServiceInstance) {
      service.on('stopService').listen((event) {
        service.stopSelf();
      });

      flutterLocalNotificationsPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    }
  }
}