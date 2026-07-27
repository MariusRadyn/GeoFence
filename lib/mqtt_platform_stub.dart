import 'package:mqtt_client/mqtt_client.dart';

MqttClient createMqttClient(String host, String clientId) {
  throw UnsupportedError('MQTT is not supported on this platform');
}

Future<bool> isMqttBrokerReachable(String host, {Duration? timeout}) async {
  return false;
}
