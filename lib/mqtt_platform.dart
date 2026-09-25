import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt_platform_stub.dart'
    if (dart.library.io) 'mqtt_platform_io.dart'
    if (dart.library.html) 'mqtt_platform_web.dart' as impl;

/// TCP MQTT for Android / desktop / Pi clients.
const int mqttTcpPort = 1883;

/// Insecure WebSocket MQTT (http:// pages + LAN IP only).
const int mqttWsPort = 9001;

/// Secure WebSocket MQTT for https:// pages to a LAN IP (self-signed Mosquitto).
const int mqttWssPort = 9002;

/// Cloudflare Tunnel / public hostname WSS (trusted cert on 443).
const int mqttWssCloudPort = 443;

MqttClient createMqttClient(String host, String clientId) =>
    impl.createMqttClient(host, clientId);

Future<bool> isMqttBrokerReachable(String host, {Duration? timeout}) =>
    impl.isMqttBrokerReachable(host, timeout: timeout);
