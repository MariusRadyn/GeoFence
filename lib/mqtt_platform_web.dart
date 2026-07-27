// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

const int _wsPort = 9001;

MqttClient createMqttClient(String host, String clientId) {
  // Mosquitto websockets path is /mqtt
  final client = MqttBrowserClient('ws://$host/mqtt', clientId);
  client.port = _wsPort;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  client.setProtocolV311();
  return client;
}

Future<bool> isMqttBrokerReachable(String host, {Duration? timeout}) async {
  if (host.isEmpty) return false;

  final deadline = timeout ?? const Duration(seconds: 2);
  final completer = Completer<bool>();
  late html.WebSocket socket;
  Timer? timer;

  void finish(bool ok) {
    if (completer.isCompleted) return;
    timer?.cancel();
    try {
      if (socket.readyState == html.WebSocket.OPEN ||
          socket.readyState == html.WebSocket.CONNECTING) {
        socket.close();
      }
    } catch (_) {}
    completer.complete(ok);
  }

  try {
    socket = html.WebSocket('ws://$host:$_wsPort/mqtt');
    timer = Timer(deadline, () => finish(false));
    socket.onOpen.listen((_) => finish(true));
    socket.onError.listen((_) => finish(false));
    socket.onClose.listen((_) {
      if (!completer.isCompleted) finish(false);
    });
  } catch (_) {
    return false;
  }

  return completer.future;
}
