import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

const int _tcpPort = 1883;

MqttClient createMqttClient(String host, String clientId) {
  final client = MqttServerClient(host, clientId);
  client.port = _tcpPort;
  client.setProtocolV311();
  return client;
}

Future<bool> isMqttBrokerReachable(String host, {Duration? timeout}) async {
  if (host.isEmpty) return false;
  try {
    final socket = await Socket.connect(
      host,
      _tcpPort,
      timeout: timeout ?? const Duration(seconds: 5),
    );
    socket.destroy();
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('MQTT TCP probe $host:$_tcpPort failed: $e');
    return false;
  }
}
