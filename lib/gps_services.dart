import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geofence/utils.dart';
import 'package:permission_handler/permission_handler.dart' as perm;

Future<Position> determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  writeLog('Check Location services ... ');
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (serviceEnabled == false) {
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
      return Future.error('Location permissions are denied');
    }
  }
  writeLog('Granted');

  if (permission == LocationPermission.deniedForever) {
    writeLog('Denied Forever');
    return Future.error(
      'Location permissions are permanently denied, we cannot request permissions.',
    );
  }

  final LocationSettings locationSettings = getLocationSettings();

  return await Geolocator.getCurrentPosition(
    locationSettings: locationSettings,
  );
}

StreamSubscription<Position> startLocationStream() {
  final LocationSettings locationSettings = getLocationSettings();

  return Geolocator.getPositionStream(locationSettings: locationSettings)
      .listen((Position? position) {
    // Foreground stream only — no background GPS service.
  });
}

/// Foreground-only location settings (no background / always-on tracking).
LocationSettings getLocationSettings() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100,
      forceLocationManager: true,
      intervalDuration: const Duration(seconds: 10),
    );
  }
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.fitness,
      distanceFilter: 100,
      pauseLocationUpdatesAutomatically: true,
      showBackgroundLocationIndicator: false,
    );
  }
  if (kIsWeb) {
    return WebSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 100,
      maximumAge: const Duration(minutes: 5),
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 100,
  );
}

Future<void> getPolylinePoints(
  double originLatitude,
  double originLongitude,
  double destLatitude,
  double destLongitude,
) async {
  final polylinePoints = PolylinePoints(apiKey: googleAPiKey);
  final response = await polylinePoints.getRouteBetweenCoordinatesV2(
    request: RoutesApiRequest(
      origin: PointLatLng(originLatitude, originLongitude),
      destination: PointLatLng(destLatitude, destLongitude),
      travelMode: TravelMode.driving,
    ),
  );
  debugPrint('${response.routes.firstOrNull?.polylinePoints}');
}

/// Kept for startup compatibility — no background GPS service is started.
Future<void> initializeGpsService() async {}

class LocationService {
  /// Requests while-in-use location (and notifications if needed).
  /// Does not request background / "always" location.
  static Future<void> requestPermissions() async {
    await perm.Permission.locationWhenInUse.request();
    await perm.Permission.notification.request();
  }

  static Future<void> stopLocationTracking() async {
    // No background GPS service to stop.
  }
}
