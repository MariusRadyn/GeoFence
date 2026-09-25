// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

bool get _useWss => html.window.location.protocol == 'https:';

/// True for dotted-decimal IPv4 (LAN base). Hostnames use Cloudflare :443.
bool _looksLikeIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}

/// Resolve WebSocket scheme/port for [host].
/// - LAN IP + https page → wss://ip:9002 (self-signed Mosquitto)
/// - LAN IP + http page  → ws://ip:9001
/// - Hostname (Cloudflare) → wss://host:443 (trusted cert)
({String scheme, int port, bool cloudflare}) mqttWsEndpoint(String host) {
  final lan = _looksLikeIpv4(host);
  if (!lan) {
    return (scheme: 'wss', port: 443, cloudflare: true);
  }
  if (_useWss) {
    return (scheme: 'wss', port: 9002, cloudflare: false);
  }
  return (scheme: 'ws', port: 9001, cloudflare: false);
}

MqttClient createMqttClient(String host, String clientId) {
  final ep = mqttWsEndpoint(host);
  // Mosquitto websockets path is /mqtt. Cloudflare Tunnel terminates TLS and
  // forwards to local ws://127.0.0.1:9001/mqtt.
  final client = MqttBrowserClient.withPort(
    '${ep.scheme}://$host/mqtt',
    clientId,
    ep.port,
  );
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  client.setProtocolV311();
  return client;
}

Future<bool> isMqttBrokerReachable(String host, {Duration? timeout}) async {
  if (host.isEmpty) return false;

  final ep = mqttWsEndpoint(host);
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
    final url = ep.port == 443
        ? '${ep.scheme}://$host/mqtt'
        : '${ep.scheme}://$host:${ep.port}/mqtt';
    socket = html.WebSocket(url);
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
