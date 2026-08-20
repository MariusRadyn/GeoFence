import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt_platform_stub.dart'
    if (dart.library.io) 'mqtt_platform_io.dart'
    if (dart.library.html) 'mqtt_platform_web.dart' as impl;

/// TCP MQTT for Android / desktop / Pi clients.
const int mqttTcpPort = 1883;

/// Insecure WebSocket MQTT (http:// pages only).
const int mqttWsPort = 9001;

/// Secure WebSocket MQTT for https:// pages (Mosquitto WSS on the base).
const int mqttWssPort = 9002;

MqttClient createMqttClient(String host, String clientId) =>
    impl.createMqttClient(host, clientId);

Future<bool> isMqttBrokerReachable(String host, {Duration? timeout}) =>
    impl.isMqttBrokerReachable(host, timeout: timeout);
