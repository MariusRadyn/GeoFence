import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'Bluetooth2.dart';

class SettingsPage extends StatefulWidget {
  final String userId;

  const SettingsPage({
    super.key,
    required this.userId
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _logPointPerMeterController = TextEditingController();
  final TextEditingController _rebateValueController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();
  bool _didInitListeners = false;
  String? bluetoothValue;
  List<ScanResult> scanResults = [];
  List<BluetoothDevice> pairedDevices = [];
  bool isScanning = false;
  BluetoothDevice? connectedDevice;
  BluetoothDevice? selectedDevice;

  @override
  void initState() {
    super.initState();

    _requestPermissions();
    _getPairedDevices();
    _initTts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

        setState(() {
          _logPointPerMeterController.text = SettingsService().settings!.logPointPerMeter.toString();
          _rebateValueController.text = SettingsService().settings!.rebateValuePerLiter.toString();
        });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!mounted) return;

    //final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    // You could set up listeners here or perform one-time operations
    // that depend on inherited widgets
    if (!_didInitListeners) {
      SettingsService().addListener(_updateControllerValues);
      //settingsProvider.addListener(_updateControllerValues);
      _didInitListeners = true;
    }

    // You can also immediately update values based on current provider state
    _updateControllerValues();
  }

  @override
  void dispose() {
    _logPointPerMeterController.dispose();
    _flutterTts.stop();
    FlutterBluePlus.stopScan();

    if (_didInitListeners) {
      Provider.of<SettingsService>(context, listen: false)
          .removeListener(_updateControllerValues);
    }
    super.dispose();
  }

  Future<void> updateSettingFields(Map<String, dynamic> updates) async {
    await SettingsService().updateFields(updates);
    //await Setting
  }
  
// Method to update controller values
  void _updateControllerValues() {
    if(!mounted) return;
    
    //final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    //if (!settingsProvider.isLoading && mounted) {
    //  setState(() {
    //    _logPointPerMeterController.text = (settingsProvider.LogPointPerMeter).toString();
    //  });
    //}
  }
  void getVoices() async {
    List<dynamic> voices = await _flutterTts.getVoices;
    print("Available Voices: $voices");
  }
  void _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  // Bluetooth
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }
  Future<void> _getPairedDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluePlus.bondedDevices;
      setState(() {
        pairedDevices = devices;
      });
    } catch (e) {
      print('Error getting paired devices: $e');
    }
  }
  Future<void> _startScan() async {
    if (await FlutterBluePlus.isSupported == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth not supported')),
      );
      return;
    }

    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results;
      });
    });

    // Start scanning
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));

    setState(() {
      isScanning = false;
    });
  }
  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() {
      isScanning = false;
    });
  }
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        connectedDevice = device;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${device.name}')),
      );

      // Discover services after connection
      List<BluetoothService> services = await device.discoverServices();
      print('Discovered ${services.length} services');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }
  Future<void> _disconnect() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      setState(() {
        connectedDevice = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnected')),
      );
    }
  }

  @override
  Widget build(BuildContext context){

    return Consumer<SettingsService>(
      builder: (context, settings, child) {

        if (settings.isLoading) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: APP_BAR_COLOR,
              foregroundColor: Colors.white,
              title: MyAppbarTitle('Settings'),
            ),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: APP_BACKGROUND_COLOR,
          appBar: AppBar(
            backgroundColor: APP_BAR_COLOR,
            foregroundColor: Colors.white,
            title: MyAppbarTitle('Settings'),
            actions: [
               IconButton(
                 icon:const Icon(
                   Icons.save,
                   size: 30
                 ),
                 onPressed: () {
                   settings.updateFields({
                     SettingLogPointPerMeter: int.parse(_logPointPerMeterController.text),
                     SettingRebateValue: double.parse(_rebateValueController.text),
                   });
                   GlobalSnackBar.show("Saved");
                 },
              ),
            ],
          ),
          body: ListView(

            children: [
              const SizedBox(height: 20),

              // Rebate Value
              MyTextOption(
                controller: _rebateValueController,
                label: 'Rebate Value',
                description: "Rebate value per kilometer",
                prefix: 'R',
              ),

              const SizedBox(height: 10),

              // logPointPerMeter
              MyTextOption(
                controller: _logPointPerMeterController,
                label: 'Log Location Interval',
                description: "Record a map location everytime you move this far in meters",
                suffix: 'm',
              ),

              const SizedBox(height: 10),

              // isVoicePromptOn
              MyToggleOption(
                  value: settings.settings!.isVoicePromptOn,
                  label: 'Voice Prompt',
                  subtitle: 'Allow me to give you vocal feedback',
                  onChanged: (bool value)=>
                  {
                    //setState(() {
                    //  _isVoicePromptOn = value;
                    //}),
                    settings.updateFields({SettingIsVoicePromptOn: value}),

                    if(value) {
                      _flutterTts.speak('Voice Prompt enabled'),
                    },
                  }
              ),

              const SizedBox(height: 10),

              // Bluetooth

              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text("Use the Bluetooth device in your vehicle to get vehicle ID"
                    "Select from your Bluetooth paired list what Bluetooth device"
                    "you connect to in this vehicle",
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,),
                softWrap: true,
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButton<BluetoothDevice>(
                        value: selectedDevice,
                        style: TextStyle(color: Colors.white),
                        hint: Text("Select bluetooth device",
                                  style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                          items: pairedDevices.map((device) {
                            String deviceName = device.platformName.isNotEmpty ? device.platformName : device.remoteId.toString();
                            return DropdownMenuItem(
                              value: device,
                              child: Text(deviceName),
                            );
                          }).toList(),
                          onChanged: (BluetoothDevice? newDevice) {
                            setState(() {
                              selectedDevice = newDevice;
                            });
                          },
                      ),
                    ),

                    SizedBox(width: 10),

                    ElevatedButton(
                        onPressed: (){
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Scanning Bluetooth')),
                          );
                          //_getPairedDevices();
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context)=> BluetoothDeviceDropdown(),
                              ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                        child: Text(
                          "Refresh",
                          style: TextStyle(
                              color: Colors.white
                          ),
                        ),
                    )
                  ],
                ),
              )

            ],
          ),
        );
      }
    );
  }
}
