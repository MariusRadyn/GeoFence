import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geofence/mqtt_platform.dart';
import 'package:geofence/utils.dart';
import 'package:mqtt_client/mqtt_client.dart';

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

  MqttClient? client;
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
  Future<bool> startService(String ip, {String? baseId}) async {
    if (baseId != null) _baseId = baseId;

    bool ok = true;

    if (!_initialized) ok = await _init(ip);
    if (ok && !isConnected) ok = await _connect();
    if (ok && !_listenerStarted) _startListener();

    return ok;
  }

  static const Duration brokerReachabilityTimeout = Duration(seconds: 2);

  /// Quick check — TCP on Android, WebSocket on web.
  Future<bool> isBrokerReachable(String ip, {Duration? timeout}) async {
    final ok = await isMqttBrokerReachable(
      ip,
      timeout: timeout ?? brokerReachabilityTimeout,
    );
    if (!ok) {
      final portHint = kIsWeb ? mqttWsPort : mqttTcpPort;
      printDebugMsg(
        'MQTT broker not reachable at $ip:$portHint '
        '(${kIsWeb ? 'WebSocket' : 'TCP'})',
      );
    }
    return ok;
  }

  Future<bool> restartService(String ip, {String? baseId}) async {
    try {
      if (baseId != null) _baseId = baseId;

      if (!await isBrokerReachable(ip)) {
        if (kIsWeb) {
          MyGlobalMessage.show(
            'Web MQTT',
            'Cannot reach base WebSocket on port $mqttWsPort.\n'
            'On the Pi run:\n'
            '  python3 MqttCredentials.py --setup\n'
            'and open firewall port $mqttWsPort.',
            MyMessageType.warning,
          );
        }
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
      if (!ok) return false;
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
    try {
      ipAdr = ip;
      autoReconnect = true;
      port = kIsWeb ? mqttWsPort : mqttTcpPort;

      if (ipAdr.isEmpty) return false;

      myDeviceId = await ClientIdManager.getClientId();

      client = createMqttClient(ipAdr, myDeviceId)
        ..logging(on: false)
        ..keepAlivePeriod = 20
        ..onConnected = _onConnected
        ..onDisconnected = _onDisconnected
        ..onAutoReconnected = _onAutoReconnected
        ..onAutoReconnect = _onAutoReconnect
        ..onSubscribed = _onSuscribed;

      client!.connectTimeoutPeriod = 4000;
      client!.autoReconnect = autoReconnect;
      client!.resubscribeOnAutoReconnect = true;
      _initialized = true;
      printDebugMsg(
        'MQTT init ${kIsWeb ? 'WebSocket' : 'TCP'} $ipAdr:$port',
      );
      return true;
    } catch (e) {
      printDebugMsg('MQTT Init Error: $e');
      return false;
    }
  }

  void _startListener() {
    if (!_listenerStarted) {
      _rxStreamListener();
      printDebugMsg('MQTT Listener Started');
    } else {
      printDebugMsg('MQTT listener - already Started');
    }
  }

  Future<bool> _connect() async {
    try {
      if (client == null) return false;

      var connectMessage = MqttConnectMessage()
          .withClientIdentifier(myDeviceId)
          .startClean()
          .withWillTopic(mqttTopicLastWill)
          .withWillMessage('offline')
          .withWillQos(MqttQos.atLeastOnce);

      final savedCreds =
          await MqttCredentialsPreferences.loadForConnect(_baseId);
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
        printDebugMsg(
          'MQTT connecting without credentials (user not logged in)',
        );
      }

      client!.connectionMessage = connectMessage;

      printDebugMsg(
        'Connecting to MQTT broker... $ipAdr:$port '
        '(${kIsWeb ? 'ws' : 'tcp'})',
      );
      await client!.connect().timeout(
        Duration(milliseconds: client!.connectTimeoutPeriod),
        onTimeout: () => throw TimeoutException('MQTT connect timed out'),
      );

      if (client!.connectionStatus != null &&
          client!.connectionStatus!.state == MqttConnectionState.connected) {
        printDebugMsg('Connected successfully!');
        return true;
      } else {
        final returnCode = client!.connectionStatus?.returnCode;
        printDebugMsg('Connection failed (return code: $returnCode)');
      }
    } on TimeoutException {
      printDebugMsg('MQTT connect timed out');
    } catch (e) {
      printDebugMsg('MQTT Connect Error: $e');
    }
    return false;
  }

  Future<void> stopMessageListener() async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    await _messageStreamController.close();
  }

  void _subscribe(String topic) {
    if (_subscribedTopics.contains(topic)) return;
    if (client == null) return;

    _subscribedTopics.add(topic);
    client!.subscribe(topic, MqttQos.atMostOnce);

    final topic0 = '$topic/$myDeviceId';
    client!.subscribe(topic0, MqttQos.atLeastOnce);
    printDebugMsg('Subscribing: $topic');
  }

  void _disconnect() {
    if (client == null) return;

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
    printDebugMsg('MQTT Connected');
  }

  void _onSuscribed(String topic) {
    printDebugMsg('Subscribed to $topic');
  }

  void _onDisconnected() {
    isConnected = false;
    printDebugMsg('MQTT Disconnected');
  }

  void _onAutoReconnect() {
    printDebugMsg('MQTT Auto-reconnecting…');
  }

  void _onAutoReconnected() {
    isConnected = true;
    _subscribedTopics.clear();
    _subscribe(mqttTopicToAndroid);
    _reconnectTimer?.cancel();
    printDebugMsg('Auto-reconnected successfully');
  }

  void _rxStreamListener() {
    if (client == null || client!.updates == null) {
      printDebugMsg('MQTT RX Stream Error: Client == null');
      return;
    }

    try {
      _updatesSubscription =
          client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
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

            if (!_messageStreamController.isClosed) {
              _messageStreamController.add(payload);
            }

            _dispatchMessage(topic, payload);
          } catch (e) {
            printDebugMsg('MQTT Rx Stream: $e');
          }
        }
      });
    } catch (e) {
      printDebugMsg('MQTT Rx Stream: $e');
    }
  }

  void onMessage(String topic, void Function(String message) callback) {}

  // -----------------------------------------------------------
  // Methods
  // -----------------------------------------------------------
  void listenForSettings(
    void Function(Map<String, dynamic>) onSettingsReceived,
  ) {
    _subscribe(mqttTopicToAndroid);
    if (client?.updates == null) return;

    printDebugMsg('Listening: $mqttTopicToAndroid');

    client!.updates!.listen((messages) {
      final mqttMsg = messages[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        mqttMsg.payload.message,
      );

      printDebugMsg('Received MQTT message: $payload');

      try {
        final jsonData = jsonDecode(payload);
        onSettingsReceived(jsonData);
      } catch (_) {
        printDebugMsg('Invalid JSON received');
      }
    });
  }

  void tx(String toDeviceId, String cmd, dynamic jsonMsg, String topic) {
    if (client == null) return;

    final payload = jsonEncode({
      mqttJsonFromDeviceId: myDeviceId,
      mqttJsonToDeviceId: toDeviceId,
      mqttJsonPayload: jsonMsg,
      mqttJsonCmd: cmd,
      mqttJsonTopic: topic,
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    printDebugMsg('MQTT TX: $payload');
  }

  void _dispatchMessage(String topic, String message) {
    if (_topicCallbacks.containsKey(topic)) {
      for (final cb in _topicCallbacks[topic]!) {
        cb(message);
      }
    }
  }
}
