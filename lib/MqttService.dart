import 'dart:async';
import 'dart:convert';
import 'package:geofence/utils.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'utils.dart';

Timer? _reconnectTimer;

class MqttService {
  String ipAdr;
  final int port;
  late String myDeviceId;
  final String mqttPin;
  bool isConnected = false;
  bool autoReconnect = false;

  late MqttServerClient client;
  final Map<String, List<void Function(String)>> _topicCallbacks = {};
  StreamSubscription? _updatesSubscription;
  final Set<String> _subscribedTopics = {};

  MqttService({
    this.ipAdr = "",
    this.port = 1883,
    this.mqttPin = "",
    this.isConnected = false,
    this.autoReconnect = false
  }){
    init();
  }

  Future<void> init() async {
     myDeviceId = await ClientIdManager.getClientId();

    client = MqttServerClient(ipAdr, myDeviceId)
      ..port = 1883
      ..logging(on: false)
      ..keepAlivePeriod = 20
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected
      ..onAutoReconnected = _onAutoReconnected
      ..onAutoReconnect = _onAutoReconnect
      ..onSubscribed = (t) => print("Subscribed to $t");

    client.setProtocolV311();

    client.connectTimeoutPeriod = 4000;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
  }


  // -----------------------------------------------------------
  // CALLBACKS
  // -----------------------------------------------------------
  void _onConnected() {
    isConnected = true;
    print("MQTT Connected");
    _reconnectTimer?.cancel(); // stop reconnection attempts
  }
  void _onDisconnected() {
    isConnected = false;
    print("MQTT Disconnected");
    if(autoReconnect) _scheduleReconnect(); // auto schedule reconnect manually
  }
  void _onAutoReconnect() {
    print("MQTT Auto-reconnecting…");
  }
  void _onAutoReconnected() {
    print("Auto-reconnected successfully");
  }
  void onMessage(String topic, void Function(String message) callback) {
    // Add subscription only once
    String _topic = topic + "/" + myDeviceId;

    if (!_subscribedTopics.contains(_topic)) {
      client.subscribe(_topic, MqttQos.atLeastOnce);
      _subscribedTopics.add(_topic);
      print("Subscribed to topic: $_topic");
    }

    // Store callback
    _topicCallbacks.putIfAbsent(_topic, () => []);
    _topicCallbacks[_topic]!.add(callback);

    print("Callback registered for topic: $_topic");
  }

  // -----------------------------------------------------------
  // Methods
  // -----------------------------------------------------------
  void getClientId() async {
    myDeviceId = await ClientIdManager.getClientId();
  }
  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectTimer = Timer.periodic(Duration(seconds: 5), (t) {
      print("Reconnecting to MQTT…");
      connect();
    });
  }
  void listenForSettings(void Function(Map<String, dynamic>) onSettingsReceived) {
      subscribe(MQTT_TOPIC_TO_ANDROID);
      //final topic = "$MQTT_TOPIC_RESPONSE/$_clientId";
      //client.subscribe(topic, MqttQos.atLeastOnce);
      //print("Subscribing: $MQTT_TOPIC_RESPONSE");

      print("Listening: $MQTT_TOPIC_TO_ANDROID");
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
  void tx(String toDeviceId, String cmd, dynamic jsonMsg, String topic) {

    final payload = jsonEncode({
      MQTT_JSON_FROM_DEVICE_ID: myDeviceId,
      MQTT_JSON_TO_DEVICE_ID: toDeviceId,
      MQTT_JSON_PAYLOAD: jsonMsg,
      MQTT_JSON_CMD: cmd,
      MQTT_JSON_TOPIC: topic
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    print("MQTT TX: $payload");
  }
  void setupMessageListener() {
    _updatesSubscription = client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      final recMsg = messages.first;
      final topic = recMsg.topic;

      final payload = MqttPublishPayload.bytesToStringAsString(
        (recMsg.payload as MqttPublishMessage).payload.message,
      );

      // Send to your registered callbacks
      _dispatchMessage(topic, payload);
    });
  }
  void _dispatchMessage(String topic, String message) {
    if (_topicCallbacks.containsKey(topic)) {
      for (final cb in _topicCallbacks[topic]!) {
        cb(message); // invoke callback
      }
    }
  }

  // -----------------------------------------------------------
  // Commands
  // -----------------------------------------------------------
  Future<bool> connect() async {
    try {
      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(myDeviceId)
          .startClean()
          .withWillTopic(MQTT_TOPIC_WILL)
          .withWillMessage('offline')
          .withWillQos(MqttQos.atLeastOnce);

      print("Connecting to MQTT broker... $ipAdr");
      await client.connect();

      if (client.connectionStatus!.state == MqttConnectionState.connected) {
        print("Connected successfully!");
        return true;

      } else {
        print("Connection failed");
      }

    } catch (e) {
      print("Error connecting: $e");

    }
    return false;
  }
  void publish(String topic, Map<String, dynamic> data) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(data));
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }
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
  void subscribe(String topic){
    //final topic = "$MQTT_TOPIC_RESPONSE/$_clientId";
    final _topic = "$topic/$myDeviceId";
    client.subscribe(_topic, MqttQos.atLeastOnce);
    print("Subscribing: $_topic");
  }
  Future<void> disconnect() async {
    // 1. Cancel the updates listener
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;

    // 2. Clear topic callbacks
    _topicCallbacks.clear();
    _subscribedTopics.clear();

    // 3. Optional: unsubscribe from all topics
    for (final topic in _subscribedTopics) {
      client.unsubscribe(topic);
    }

    // 4. Disconnect the client
    _reconnectTimer?.cancel();
    client.disconnect();
  }

}


