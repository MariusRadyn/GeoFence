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
  int _autoReconnectAttempts = 0;
  DateTime? _autoReconnectWindowStart;

  /// True only when the broker socket is actually connected (not a stale flag).
  bool get isBrokerConnected =>
      isConnected &&
      client != null &&
      client!.connectionStatus?.state == MqttConnectionState.connected;

  /// Last failure reason from [restartService] / [_connect] (for UI messages).
  String? lastError;

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

  static const Duration brokerReachabilityTimeout = Duration(seconds: 5);

  /// Strip scheme / path / trailing port so "http://192.168.1.10:1883/" works.
  static String normalizeHost(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;

    s = s.replaceFirst(RegExp(r'^(mqtts?|wss?|https?)://', caseSensitive: false), '');
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);

    // Drop ":port" for IPv4 / hostnames (not IPv6).
    if (!s.startsWith('[')) {
      final colon = s.lastIndexOf(':');
      if (colon > 0 && int.tryParse(s.substring(colon + 1)) != null) {
        s = s.substring(0, colon);
      }
    }
    return s.trim();
  }

  /// Quick check — TCP on Android, WebSocket on web.
  Future<bool> isBrokerReachable(String ip, {Duration? timeout}) async {
    final ok = await isMqttBrokerReachable(
      ip,
      timeout: timeout ?? brokerReachabilityTimeout,
    );
    if (!ok) {
      final portHint = kIsWeb
          ? (Uri.base.scheme == 'https' ? mqttWssPort : mqttWsPort)
          : mqttTcpPort;
      printDebugMsg(
        'MQTT broker not reachable at $ip:$portHint '
        '(${kIsWeb ? 'WebSocket' : 'TCP'})',
      );
    }
    return ok;
  }

  Future<bool> restartService(String ip, {String? baseId}) async {
    lastError = null;
    try {
      if (baseId != null) _baseId = baseId;

      final trimmedIp = normalizeHost(ip);
      if (trimmedIp.isEmpty) {
        lastError = 'No IP address';
        return false;
      }

      // Probe is advisory only — some networks fail the TCP check while MQTT
      // connect still works (and vice versa). Always attempt a real connect.
      final reachable = await isBrokerReachable(trimmedIp);
      if (!reachable) {
        printDebugMsg(
          'MQTT reachability probe failed for $trimmedIp — '
          'attempting MQTT connect anyway',
        );
      }

      autoReconnect = false;

      await _updatesSubscription?.cancel();
      _updatesSubscription = null;

      _disconnect();
      _resetAutoReconnectBudget();

      _topicCallbacks.clear();
      _subscribedTopics.clear();

      bool ok = true;
      ok = await _init(trimmedIp);
      if (!ok) {
        lastError ??= 'MQTT init failed';
        return false;
      }
      ok = await _connect();

      _listenerStarted = false;
      _startListener();

      if (!ok) {
        final portHint = kIsWeb
            ? (Uri.base.scheme == 'https' ? mqttWssPort : mqttWsPort)
            : mqttTcpPort;
        if (kIsWeb && Uri.base.scheme == 'https') {
          lastError ??=
              'Cannot open secure MQTT (wss://$trimmedIp:$portHint).\n'
              '1) On phone Chrome open https://$trimmedIp:$portHint\n'
              '2) Tap Advanced → Proceed (trust the base certificate once)\n'
              '3) Come back here and connect again.\n'
              'Also check Pi Mosquitto is listening on 9002 and UFW allows it.';
          MyGlobalMessage.show('Web MQTT', lastError!, MyMessageType.warning);
        } else {
          lastError ??= !reachable
              ? 'Cannot reach base at $trimmedIp:$portHint.\n'
                  'Phone must be on the same Wi‑Fi as the base.\n'
                  'Check the IP (cloud button) and that Mosquitto is running.'
              : 'MQTT broker refused the connection (check MQTT user/password).';
        }
      }
      return ok;
    } catch (e) {
      lastError = '$e';
      MyGlobalMessage.show('Error', '$e', MyMessageType.debug);
      return false;
    }
  }

  Future<bool> _init(String ip) async {
    try {
      ipAdr = ip;
      autoReconnect = true;
      port = kIsWeb
          ? (Uri.base.scheme == 'https' ? mqttWssPort : mqttWsPort)
          : mqttTcpPort;

      if (ipAdr.isEmpty) return false;

      myDeviceId = await _resolveClientId();

      client = createMqttClient(ipAdr, myDeviceId)
        ..logging(on: false)
        ..keepAlivePeriod = 20
        ..onConnected = _onConnected
        ..onDisconnected = _onDisconnected
        ..onAutoReconnected = _onAutoReconnected
        ..onAutoReconnect = _onAutoReconnect
        ..onSubscribed = _onSuscribed
        ..onSubscribeFail = (topic) {
          printDebugMsg('MQTT subscribe FAILED: $topic');
        };

      client!.connectTimeoutPeriod = 8000;
      client!.autoReconnect = autoReconnect;
      client!.resubscribeOnAutoReconnect = true;
      _initialized = true;
      printDebugMsg(
        'MQTT init ${kIsWeb ? (Uri.base.scheme == 'https' ? 'WSS' : 'WS') : 'TCP'} $ipAdr:$port',
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
        lastError = null;
        return true;
      } else {
        final returnCode = client!.connectionStatus?.returnCode;
        printDebugMsg('Connection failed (return code: $returnCode)');
        lastError =
            'MQTT connect failed (code: $returnCode). '
            'Check broker credentials for this base.';
      }
    } on TimeoutException {
      printDebugMsg('MQTT connect timed out');
      lastError = 'Base connect timed out';
    } catch (e) {
      printDebugMsg('MQTT Connect Error: $e');
      lastError = 'Base connect error: $e';
    }
    return false;
  }

  /// Stable app id (prefs) plus a short web session suffix so hot reload /
  /// multiple tabs do not fight the broker with the same MQTT client id.
  Future<String> _resolveClientId() async {
    final baseId = await ClientIdManager.getClientId();
    if (!kIsWeb) return baseId;
    final suffix =
        (DateTime.now().millisecondsSinceEpoch % 0x10000).toRadixString(16);
    return '${baseId}_w$suffix';
  }

  void _resetAutoReconnectBudget() {
    _autoReconnectAttempts = 0;
    _autoReconnectWindowStart = null;
  }

  bool _shouldPauseAutoReconnect() {
    final now = DateTime.now();
    final windowStart = _autoReconnectWindowStart;
    if (windowStart == null ||
        now.difference(windowStart) > const Duration(seconds: 30)) {
      _autoReconnectWindowStart = now;
      _autoReconnectAttempts = 0;
    }
    _autoReconnectAttempts++;
    return _autoReconnectAttempts > 8;
  }

  Future<void> stopMessageListener() async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    await _messageStreamController.close();
  }

  void _subscribe(String topic) {
    if (client == null) return;

    // Single wildcard sub — covers mqtt/to/android and mqtt/to/android/{deviceId}.
    // Do not also subscribe to those paths separately; overlapping subs deliver
    // the same publish twice and duplicate UI handlers (e.g. two OK dialogs).
    _subscribeOne('$topic/#', MqttQos.atLeastOnce);
    printDebugMsg('MQTT listening on $topic/#');
  }

  void _subscribeOne(String topic, MqttQos qos) {
    if (client == null) return;
    if (_subscribedTopics.contains(topic)) return;

    _subscribedTopics.add(topic);
    client!.subscribe(topic, qos);
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
    _resetAutoReconnectBudget();
    _subscribedTopics.clear();
    _subscribe(mqttTopicToAndroid);
    _reconnectTimer?.cancel();
    printDebugMsg('MQTT connected ($myDeviceId → $ipAdr:$port)');
  }

  void _onSuscribed(String topic) {
    // Broker ack — avoid per-topic log spam on reconnect.
  }

  void _onDisconnected() {
    isConnected = false;
    printDebugMsg('MQTT disconnected');
  }

  void _onAutoReconnect() {
    if (_shouldPauseAutoReconnect()) {
      printDebugMsg(
        'MQTT auto-reconnect paused (connection unstable). '
        'Refresh the page, then connect once from Base Stations.',
      );
      if (client != null) {
        client!.autoReconnect = false;
      }
      autoReconnect = false;
      return;
    }
    printDebugMsg('MQTT auto-reconnecting…');
  }

  void _onAutoReconnected() {
    isConnected = true;
    _resetAutoReconnectBudget();
    // resubscribeOnAutoReconnect restores topics; skip manual re-subscribe.
    _reconnectTimer?.cancel();
    printDebugMsg('MQTT auto-reconnected');
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

            printDebugMsg('MQTT RX [$topic]: $payload');

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

  /// Publish to the broker. Returns false if not connected or publish failed.
  bool tx(String toDeviceId, String cmd, dynamic jsonMsg, String topic) {
    if (!isBrokerConnected) {
      lastError = 'MQTT is not connected';
      printDebugMsg('MQTT TX skipped (not connected): $cmd → $toDeviceId');
      return false;
    }

    try {
      final payload = jsonEncode({
        mqttJsonFromDeviceId: myDeviceId,
        mqttJsonToDeviceId: toDeviceId,
        mqttJsonPayload: jsonMsg,
        mqttJsonCmd: cmd,
        mqttJsonTopic: topic,
      });

      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      final bytes = builder.payload;
      if (bytes == null || bytes.isEmpty) {
        lastError = 'MQTT payload encode failed';
        return false;
      }

      // QoS0 on web avoids PUBACK stalls some browsers hit on WSS.
      final qos = kIsWeb ? MqttQos.atMostOnce : MqttQos.atLeastOnce;
      final msgId = client!.publishMessage(topic, qos, bytes);
      printDebugMsg('MQTT TX (id=$msgId): $payload');
      lastError = null;
      return true;
    } catch (e) {
      lastError = 'MQTT publish failed: $e';
      printDebugMsg('MQTT TX error: $e');
      return false;
    }
  }

  void _dispatchMessage(String topic, String message) {
    if (_topicCallbacks.containsKey(topic)) {
      for (final cb in _topicCallbacks[topic]!) {
        cb(message);
      }
    }
  }
}
