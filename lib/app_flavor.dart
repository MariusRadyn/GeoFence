import 'package:flutter/foundation.dart' show kIsWeb;

/// Build flavor selected with:
/// `--dart-define=APP_FLAVOR=full` or `APP_FLAVOR=reporting`
///
/// If unset: **web → reporting**, other platforms → **full**.
enum AppFlavor {
  /// Full field app: tracking, geofence, base stations, IoT monitors, reports.
  full,

  /// Reporting SKU (web / desktop store): history, IoT data, wages, operators.
  reporting,
}

class AppConfig {
  static const String _flavorRaw = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: '',
  );

  static final AppFlavor flavor = _resolve();

  static AppFlavor _resolve() {
    if (_flavorRaw.isEmpty) {
      return kIsWeb ? AppFlavor.reporting : AppFlavor.full;
    }
    return _parse(_flavorRaw);
  }

  static AppFlavor _parse(String value) {
    switch (value.toLowerCase().trim()) {
      case 'reporting':
      case 'report':
        return AppFlavor.reporting;
      case 'full':
      default:
        return AppFlavor.full;
    }
  }

  static bool get isFull => flavor == AppFlavor.full;
  static bool get isReporting => flavor == AppFlavor.reporting;

  /// Product name shown in UI for this flavor.
  static String get appTitle => 'Limitless IOT';

  // ---- Feature flags (reporting vs full) ----

  // ---- Android Features ----
  static bool get showLiveTracking => isFull;
  static bool get showGeoFenceSetup => isFull;
  static bool get showBaseStations => true;
  static bool get showIotMonitors => true;

  // ---- Allways Features ----
  static bool get showIotDataReport => true;
  static bool get showOperators => true;
  static bool get showSettings => true;
  static bool get showTrackingHistory => true;
  static bool get showWages => true;
  
  // ---- Web Features ----
  static bool get addTrackingHistory => isReporting;
  static bool get addWages => isReporting;

  /// BLE is Android/iOS only — never on web (not supported / not published).
  static bool get enableBluetooth => !kIsWeb;

  /// Field / device services (MQTT, GPS background) only for full flavor.
  static bool get enableFieldServices => isFull;
}
