import 'dart:async';
import 'dart:convert';
import 'package:geofence/utils.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

Timer? _reconnectTimer;

class MqttService {
  final String ipAdr;
  final int port;
  late String _clientId;
  final String mqttPin;

  late MqttServerClient client;

  MqttService({
    required this.ipAdr,
    this.port = 1883,
    this.mqttPin = ""
  }){}

  /// Call this BEFORE connect()
  Future<void> init() async {
    _clientId = await ClientIdManager.getClientId();

    client = MqttServerClient(ipAdr, _clientId)
      ..port = 1883
      ..logging(on: false)
      ..keepAlivePeriod = 20
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected
      ..onSubscribed = (t) => print("Subscribed to $t");

    client.onAutoReconnect = _onAutoReconnect;
    client.onAutoReconnected = _onAutoReconnected;
    client.setProtocolV311();

    client.connectTimeoutPeriod = 4000;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(_clientId)
        .startClean();
        //.withWillQos(MqttQos.atLeastOnce);
  }

  /// Connect to Raspberry Pi MQTT
  Future<bool> connect() async {
    try {

      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier("geoAndroidMqtt")
          .startClean();
          //.withWillQos(MqttQos.atLeastOnce);

      print("Connecting to MQTT broker... $ipAdr");
      await client.connect();
    } catch (e) {
      print("Error connecting: $e");
      return false;
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      print("Connected successfully!");
      return true;
    } else {
      print("Connection failed");
      return false;
    }
  }

  // -----------------------------------------------------------
  // CALLBACKS
  // -----------------------------------------------------------
  void _onConnected() {
    print("MQTT CONNECTED");
    _reconnectTimer?.cancel(); // stop reconnection attempts
  }
  void _onDisconnected() {
    print("MQTT DISCONNECTED");
    _scheduleReconnect(); // auto schedule reconnect manually
  }
  void _onAutoReconnect() {
    print("Auto-reconnecting…");
  }
  void _onAutoReconnected() {
    print("Auto-reconnected successfully");
  }

  // -----------------------------------------------------------
  // MANUAL RECONNECT TIMER (failsafe)
  // -----------------------------------------------------------
  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectTimer = Timer.periodic(Duration(seconds: 5), (t) {
      print("Reconnecting to MQTT…");
    //  connect();
    });
  }

  // -----------------------------------------------------------
  // SUBSCRIBE + LISTEN
  // -----------------------------------------------------------
  void listen(String topic, void Function(String message) callback) {
    client.subscribe(topic, MqttQos.atLeastOnce);

    client.updates!.listen((messages) {
      final payload =
      MqttPublishPayload.bytesToStringAsString(
        (messages[0].payload as MqttPublishMessage).payload.message,
      );

      callback(payload);
    });
  }

  /// Listen for settings responses from Raspberry Pi
  void listenForSettings(void Function(Map<String, dynamic>) onSettingsReceived) {
    final topic = "$MQTT_TOPIC_RESPONSE/$_clientId";
    client.subscribe(topic, MqttQos.atLeastOnce);
    print("Subscribing: $MQTT_TOPIC_RESPONSE");


    print("Listening: $MQTT_TOPIC_RESPONSE");
    client.updates!.listen((messages) {
      final mqttMsg = messages[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        mqttMsg.payload.message,
      );

      print("Received MQTT message: $payload");

      try {
        final jsonData = jsonDecode(payload);
        onSettingsReceived(jsonData);
      } catch (_) {
        print("Invalid JSON received");
      }
    });
  }

  /// Request settings from Raspberry Pi
  void requestSettings() {

    final payload = jsonEncode({
      "clientId": _clientId,
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    print("Requesting: $MQTT_TOPIC_REQUEST");
    client.publishMessage(MQTT_TOPIC_REQUEST, MqttQos.atLeastOnce, builder.payload!);

    print("Requested settings from Raspberry Pi");
  }


  // -----------------------------------------------------------
  // PUBLISH
  // -----------------------------------------------------------
  void publish(String topic, Map<String, dynamic> data) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(data));
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

}

class testMqttService {
  String ipAdr = '';
  late MqttServerClient client;
  final int port;
  final String clientId;
  final String mqttPin;

  testMqttService({
    required this.ipAdr,
    this.port = 1883,
    this.clientId = "",
    this.mqttPin = ""
  }){
    client = MqttServerClient(ipAdr, 'flutter_client');
    client.port = 1883;
    client.keepAlivePeriod = 20;
    client.logging(on: false);
  }

  Future<void> connect() async {
    client.onDisconnected = () => print("MQTT Disconnected");
    client.onConnected = () => print("MQTT Connected $ipAdr");
    client.onSubscribed = (topic) => print("Subscribed to $topic");

    final connMessage = MqttConnectMessage()
        .withClientIdentifier("geoAndroidMqtt")
        .startClean();

    client.connectionMessage = connMessage;

    try {
      await client.connect();
    } catch (e) {
      print("Error: $e");
      client.disconnect();
    }

    print("Subscribe: $MQTT_TOPIC_RESPONSE");

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      client.subscribe(MQTT_TOPIC_RESPONSE, MqttQos.atLeastOnce);

      client.updates!.listen((messages) {
        final MqttReceivedMessage recMsg = messages[0];
        final MqttPublishMessage payload = recMsg.payload;
        final String text =
        MqttPublishPayload.bytesToStringAsString(payload.payload.message);

        print("RX from MQTT: $text");
      });

      publish("Hello from Flutter!");
    }
  }
  void publish(String msg) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(msg);

    client.publishMessage(MQTT_TOPIC_REQUEST, MqttQos.atLeastOnce, builder.payload!);
  }
}
