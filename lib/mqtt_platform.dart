import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt_platform_stub.dart'
    if (dart.library.io) 'mqtt_platform_io.dart'
    if (dart.library.html) 'mqtt_platform_web.dart' as impl;

/// TCP MQTT for Android / desktop / Pi clients.
const int mqttTcpPort = 1883;

/// WebSocket MQTT for Flutter web (matches Mosquitto on the base).
const int mqttWsPort = 9001;

MqttClient createMqttClient(String host, String clientId) =>
    impl.createMqttClient(host, clientId);

Future<bool> isMqttBrokerReachable(String host, {Duration? timeout}) =>
    impl.isMqttBrokerReachable(host, timeout: timeout);
