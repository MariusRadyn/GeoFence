import 'dart:async';
import 'dart:convert';
import 'package:geofence/utils.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

Timer? _reconnectTimer;

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  late String ipAdr;
  late int port;
  late String myDeviceId;

  bool isConnected = false;
  bool _listenerStarted = false;
  bool autoReconnect = false;
  bool _initialized = false;

  MqttServerClient? client;
  final Map<String, List<void Function(String)>> _topicCallbacks = {};
  StreamSubscription? _updatesSubscription;
  final Set<String> _subscribedTopics = {};

  final _messageStreamController = StreamController<String>.broadcast();
  Stream<String> get messageStream => _messageStreamController.stream;


  void dispose() {
    _messageStreamController.close();
  }

  // -----------------------------------------------------------
  // Initialize
  // -----------------------------------------------------------
  Future<bool> startService(String ip) async{
    bool ok = true;

    if(!_initialized) ok = await _init(ip);
    if(ok && !isConnected) ok = await _connect();
    if(ok && !_listenerStarted) _startListener();

    return ok;
  }
  Future<bool> _init(String ip) async {

    try{
      ipAdr = ip;
      autoReconnect = true;
      port = 1883;

      if(ipAdr.isEmpty) return false;

      myDeviceId = await ClientIdManager.getClientId();

      client = MqttServerClient(ipAdr, myDeviceId)
        ..port = port
        ..logging(on: false)
        ..keepAlivePeriod = 20
        ..onConnected = _onConnected
        ..onDisconnected = _onDisconnected
        ..onAutoReconnected = _onAutoReconnected
        ..onAutoReconnect = _onAutoReconnect
        ..onSubscribed = (t) => printMsg("Subscribed to $t");

      client!.setProtocolV311();

      client!.connectTimeoutPeriod = 4000;
      client!.autoReconnect = autoReconnect;
      client!.resubscribeOnAutoReconnect = true;
      _initialized = true;
      return true;
    }
    catch (e)
    {
      printMsg("MQTT Init Error: $e");
      return false;
    }

  }
  void _startListener() {
    if (!_listenerStarted) {
      //_listenerStarted = true inside _rxStreamListener();
      //baseService.setConnectedByIp(ip, true);

      _rxStreamListener();
      printMsg("MQTT Listener Started");
    }
    else {
      printMsg("MQTT listener - already Started");
    }
  }
  Future<bool> _connect() async {
    try {
      if(client == null) return false;

      client!.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(myDeviceId)
          .startClean()
          .withWillTopic(MQTT_TOPIC_WILL)
          .withWillMessage('offline')
          .withWillQos(MqttQos.atLeastOnce);

      printMsg("Connecting to MQTT broker... $ipAdr");
      await client!.connect();

      if (client!.connectionStatus != null && client!.connectionStatus!.state == MqttConnectionState.connected) {
        printMsg("Connected successfully!");
        return true;
      } else {
        printMsg("Connection failed");
      }

    } catch (e) {
      printMsg("MQTT Connect Error: $e");

    }
    return false;
  }
  Future<bool> reconnect(String ip) async {
    try {
      isConnected = false;
      _initialized = false;
      _listenerStarted = false;
      _updatesSubscription!.cancel();

      _disconnect();
      return await startService(ip);

    } catch (e) {
      print("Error connecting: $e");
      return false;
    }
  }
  Future<void> stopMessageListener() async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    await _messageStreamController.close();
  }
  void _subscribe(String topic){
    if (_subscribedTopics.contains(topic)) return;
    if(client == null)return;

    _subscribedTopics.add(topic);
    client!.subscribe(topic, MqttQos.atMostOnce);

    final _topic = "$topic/$myDeviceId";
    client!.subscribe(_topic, MqttQos.atLeastOnce);
    printMsg("Subscribing: $topic");
  }
  void _disconnect() {
    if(client != null) return;

    // Disconnect if connected
    if (_initialized && client!.connectionStatus?.state == MqttConnectionState.connected) {
      client!.disconnect();
      _initialized = false;
    }

    // // Cancel the updates listener
    // await _updatesSubscription?.cancel();
    // _updatesSubscription = null;
    //
    // // Clear topic callbacks
    // _topicCallbacks.clear();
    // _subscribedTopics.clear();
    //
    // // Optional: unsubscribe from all topics
    // for (final topic in _subscribedTopics) {
    //   client.unsubscribe(topic);
    // }
    //
    // // Disconnect the client
    // _reconnectTimer?.cancel();
    // client.disconnect();
    //
    // isConnected = false;
  }

  // -----------------------------------------------------------
  // CALLBACKS
  // -----------------------------------------------------------
  void _onConnected() {
    isConnected = true;

    _subscribe(MQTT_TOPIC_TO_ANDROID);

    print("MQTT Connected");
    _reconnectTimer?.cancel(); // stop reconnection attempts
  }
  void _onDisconnected() {
    isConnected = false;
    print("MQTT Disconnected");
    dispose();
    if(autoReconnect) _scheduleReconnect(); // auto schedule reconnect manually
  }
  void _onAutoReconnect() {
    print("MQTT Auto-reconnecting…");
  }
  void _onAutoReconnected() {
    print("Auto-reconnected successfully");
  }
  void _rxStreamListener() {
    if (client == null || client!.updates == null) {
      printMsg("MQTT RX Stream Error: Client == null");
      return;
    }

    printMsg("MQTT RX Stream Started");
    try{
      _updatesSubscription = client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
        _listenerStarted = true;

        for (final recMsg in messages) {
          try {
            final topic = recMsg.topic;

            if (recMsg.payload is! MqttPublishMessage) {
              continue;
            }

            final publishMessage = recMsg.payload as MqttPublishMessage;
            final payload = MqttPublishPayload.bytesToStringAsString(
              publishMessage.payload.message,
            );

            // Push message to the stream
            if (!_messageStreamController.isClosed) {
              _messageStreamController.add(payload);
            }

            // Dispatch to callbacks
            _dispatchMessage(topic, payload);
            printMsg('MQTT message received on $topic: $payload');
          }
          catch (e) {
            printMsg('MQTT Rx Stream: $e');
          }
        }
      });
    }
    catch (e){
        printMsg('MQTT Rx Stream: $e');
    }

  }
  void onMessage(String topic, void Function(String message) callback) {
  //   // Add subscription only once
  //   String _topic = topic + "/" + myDeviceId;
  //
  //   if (!_subscribedTopics.contains(_topic)) {
  //     client.subscribe(_topic, MqttQos.atLeastOnce);
  //     _subscribedTopics.add(_topic);
  //     print("Subscribed to topic: $_topic");
  //   }
  //
  //   // Store callback
  //   _topicCallbacks.putIfAbsent(_topic, () => []);
  //   _topicCallbacks[_topic]!.add(callback);
  //
  //   print("Callback registered for topic: $_topic");
  }

  // -----------------------------------------------------------
  // Methods
  // -----------------------------------------------------------
  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectTimer = Timer.periodic(Duration(seconds: 5), (t) {
      _connect();
      printMsg("Reconnecting to MQTT…");
    });
  }
  void listenForSettings(void Function(Map<String, dynamic>) onSettingsReceived) {
      _subscribe(MQTT_TOPIC_TO_ANDROID);
      //final topic = "$MQTT_TOPIC_RESPONSE/$_clientId";
      //client.subscribe(topic, MqttQos.atLeastOnce);
      //print("Subscribing: $MQTT_TOPIC_RESPONSE");
      if(client?.updates == null) return;

      print("Listening: $MQTT_TOPIC_TO_ANDROID");

      client!.updates!.listen((messages) {
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
    if(client == null) return;

    final payload = jsonEncode({
      MQTT_JSON_FROM_DEVICE_ID: myDeviceId,
      MQTT_JSON_TO_DEVICE_ID: toDeviceId,
      MQTT_JSON_PAYLOAD: jsonMsg,
      MQTT_JSON_CMD: cmd,
      MQTT_JSON_TOPIC: topic
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    print("MQTT TX: $payload");
  }
  void _dispatchMessage(String topic, String message) {
    if (_topicCallbacks.containsKey(topic)) {
      for (final cb in _topicCallbacks[topic]!) {
        cb(message); // invoke callback
      }
    }
  }

// void publish(String topic, Map<String, dynamic> data) {
//   if(client == null) return;
//
//   final builder = MqttClientPayloadBuilder();
//   builder.addString(jsonEncode(data));
//   client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
// }
// Future<bool> connectAndListen(String ip) async {
//   if (!_listenerStarted) {
//     if (ip.isEmpty) return false;
//
//     if (!isConnected) {
//       final ok = await connect(ip);
//       if(!ok) return false;
//
//       printMsg("MQTT Listener Started");
//       //baseService.setConnectedByIp(ip, true);
//
//       if (!_listenerStarted) {
//         _listenerStarted = true;
//         _startListener();
//         printMsg("MQTT Listener Started");
//       }
//       else {
//         printMsg("MQTT listener - already Started");
//       }
//       return true;
//     }
//     return true;
//   }
//   return true;
// }
// void listen(String topic, void Function(String message) callback) {
//   client.subscribe(topic, MqttQos.atLeastOnce);
//
//   client.updates!.listen((messages) {
//     final payload =
//     MqttPublishPayload.bytesToStringAsString(
//       (messages[0].payload as MqttPublishMessage).payload.message,
//     );
//
//     callback(payload);
//   });
// }
}


