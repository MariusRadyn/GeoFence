import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geofence/utils.dart';

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