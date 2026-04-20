
import 'package:flutter/widgets.dart';
import 'MqttService.dart';

class AppLifecycleHandler with WidgetsBindingObserver {
  final MqttService mqttService;

  AppLifecycleHandler(this.mqttService);

  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        //mqttService.onAppResumed();
        break;

      case AppLifecycleState.paused:
        //mqttService.onAppBackgrounded();
        break;

      case AppLifecycleState.detached:
        //mqttService.dispose();
        break;

      case AppLifecycleState.inactive:
        break;

      case AppLifecycleState.hidden:
        break;

    }
  }
}
