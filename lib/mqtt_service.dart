import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
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
  String? _baseId;

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
  Future<bool> startService(String ip, {String? baseId}) async{
    if (baseId != null) _baseId = baseId;

    bool ok = true;

    if(!_initialized) ok = await _init(ip);
    if(ok && !isConnected) ok = await _connect();
    if(ok && !_listenerStarted) _startListener();

    return ok;
  }
  static const Duration brokerReachabilityTimeout = Duration(seconds: 2);

  /// Quick TCP check — fails fast when the base station is off or unreachable.
  Future<bool> isBrokerReachable(String ip, {Duration? timeout}) async {
    if (ip.isEmpty) return false;

    try {
      final socket = await Socket.connect(
        ip,
        1883,
        timeout: timeout ?? brokerReachabilityTimeout,
      );
      await socket.close();
      return true;
    } catch (e) {
      printDebugMsg('MQTT broker not reachable at $ip:1883 ($e)');
      return false;
    }
  }

  Future<bool> restartService(String ip, {String? baseId}) async {
    try {
      if (baseId != null) _baseId = baseId;

      if (!await isBrokerReachable(ip)) {
        return false;
      }

      autoReconnect = false;

      await _updatesSubscription?.cancel();
      _updatesSubscription = null;

      _disconnect();

      _topicCallbacks.clear();
      _subscribedTopics.clear();

      bool ok = true;
      ok = await _init(ip);
      ok = await _connect();

      _listenerStarted = false;
      _startListener();

      return ok;

    } catch (e) {
      MyGlobalMessage.show('Error', '$e', MyMessageType.debug);
      return false;
    }
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
        ..onSubscribed = _onSuscribed;

      //..onSubscribed = (t) => printMsg("Subscribed to $t");
      client!.setProtocolV311();

      client!.connectTimeoutPeriod = 4000;
      client!.autoReconnect = autoReconnect;
      client!.resubscribeOnAutoReconnect = true;
      _initialized = true;
      return true;
    }
    catch (e)
    {
      printDebugMsg("MQTT Init Error: $e");
      return false;
    }

  }
  void _startListener() {
    if (!_listenerStarted) {
      //Set _listenerStarted inside _rxStreamListener();

      _rxStreamListener();
      printDebugMsg("MQTT Listener Started");
    }
    else {
      printDebugMsg("MQTT listener - already Started");
    }
  }
  Future<bool> _connect() async {
    try {
      if(client == null) return false;

      var connectMessage = MqttConnectMessage()
          .withClientIdentifier(myDeviceId)
          .startClean()
          .withWillTopic(mqttTopicLastWill)
          .withWillMessage('offline')
          .withWillQos(MqttQos.atLeastOnce);

      final savedCreds = await MqttCredentialsPreferences.loadForConnect(_baseId);
      String? user = savedCreds.user;
      String? password = savedCreds.password;
      var credentialSource = 'prefs';

      if (user == null ||
          user.isEmpty ||
          password == null ||
          password.isEmpty) {
        if (_baseId != null && _baseId!.isNotEmpty) {
          final synced =
              await MqttCredentialsPreferences.syncFromFirestore(_baseId!);
          if (synced) {
            final firestoreCreds =
                await MqttCredentialsPreferences.load(_baseId!);
            user = firestoreCreds.user;
            password = firestoreCreds.password;
            credentialSource = 'firestore';
          }
        }
      }

      if (user == null ||
          user.isEmpty ||
          password == null ||
          password.isEmpty) {
        final firebaseUser = FirebaseAuth.instance.currentUser;
        if (firebaseUser != null) {
          user = firebaseUser.uid;
          password = await firebaseUser.getIdToken();
          credentialSource = 'firebase';
        } else {
          credentialSource = 'none';
        }
      }

      if (user != null &&
          user.isNotEmpty &&
          password != null &&
          password.isNotEmpty) {
        connectMessage = connectMessage.authenticateAs(user, password);
        printDebugMsg('MQTT connecting with $credentialSource user: $user');
      } else {
        printDebugMsg('MQTT connecting without credentials (user not logged in)');
      }

      client!.connectionMessage = connectMessage;

      printDebugMsg("Connecting to MQTT broker... $ipAdr");
      await client!.connect().timeout(
        Duration(milliseconds: client!.connectTimeoutPeriod),
        onTimeout: () => throw TimeoutException('MQTT connect timed out'),
      );

      if (client!.connectionStatus != null && client!.connectionStatus!.state == MqttConnectionState.connected) {
        printDebugMsg("Connected successfully!");
        return true;
      } else {
        final returnCode = client!.connectionStatus?.returnCode;
        printDebugMsg("Connection failed (return code: $returnCode)");
      }

    } on TimeoutException {
      printDebugMsg("MQTT connect timed out");
    } catch (e) {
      printDebugMsg("MQTT Connect Error: $e");

    }
    return false;
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

    final topic0 = "$topic/$myDeviceId";
    client!.subscribe(topic0, MqttQos.atLeastOnce);
    printDebugMsg("Subscribing: $topic");
  }
  void _disconnect() {
    if (client == null) return;

    // Disable built-in auto-reconnect BEFORE disconnect, otherwise the old
    // client keeps reconnecting with the same client ID and fights a new one.
    client!.autoReconnect = false;
    autoReconnect = false;
    _reconnectTimer?.cancel();

    try {
      if (client!.connectionStatus?.state == MqttConnectionState.connected ||
          client!.connectionStatus?.state == MqttConnectionState.connecting) {
        client!.disconnect();
      }
    } catch (e) {
      printDebugMsg('MQTT disconnect error: $e');
    }

    client = null;
    isConnected = false;
  }

  // -----------------------------------------------------------
  // CALLBACKS
  // -----------------------------------------------------------
  void _onConnected() {
    isConnected = true;
    _subscribedTopics.clear();
    _subscribe(mqttTopicToAndroid);
    _reconnectTimer?.cancel();
    printDebugMsg("MQTT Connected");
  }
  void _onSuscribed(String topic) {
    printDebugMsg("Subscribed to $topic");
  }
  void _onDisconnected() {
    isConnected = false;
    printDebugMsg("MQTT Disconnected");
    // Do NOT schedule a manual reconnect when client.autoReconnect is enabled —
    // that causes a dual-reconnect loop (same client ID fights itself).
  }
  void _onAutoReconnect() {
    printDebugMsg("MQTT Auto-reconnecting…");
  }
  void _onAutoReconnected() {
    isConnected = true;
    _subscribedTopics.clear();
    _subscribe(mqttTopicToAndroid);
    _reconnectTimer?.cancel();
    printDebugMsg("Auto-reconnected successfully");
  }
  void _rxStreamListener() {
    if (client == null || client!.updates == null) {
      printDebugMsg("MQTT RX Stream Error: Client == null");
      return;
    }

    //printMsg("MQTT RX Stream Started");
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
            //printMsg('MQTT RX Stream: $topic: $payload');
          }
          catch (e) {
            printDebugMsg('MQTT Rx Stream: $e');
          }
        }
      });
    }
    catch (e){
        printDebugMsg('MQTT Rx Stream: $e');
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
  void listenForSettings(void Function(Map<String, dynamic>) onSettingsReceived) {
      _subscribe(mqttTopicToAndroid);
      if(client?.updates == null) return;

      printDebugMsg("Listening: $mqttTopicToAndroid");

      client!.updates!.listen((messages) {
        final mqttMsg = messages[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          mqttMsg.payload.message,
        );

        printDebugMsg("Received MQTT message: $payload");

        try {
          final jsonData = jsonDecode(payload);
          onSettingsReceived(jsonData);
        } catch (_) {
          printDebugMsg("Invalid JSON received");
        }
      });
    }
  void tx(String toDeviceId, String cmd, dynamic jsonMsg, String topic) {
    if(client == null) return;

    final payload = jsonEncode({
      mqttJsonFromDeviceId: myDeviceId,
      mqttJsonToDeviceId: toDeviceId,
      mqttJsonPayload: jsonMsg,
      mqttJsonCmd: cmd,
      mqttJsonTopic: topic
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    printDebugMsg("MQTT TX: $payload");
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


