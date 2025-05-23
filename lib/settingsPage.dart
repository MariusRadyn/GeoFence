import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';

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
  TextEditingController _logPointPerMeterController = TextEditingController();
  TextEditingController _rebateValueController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();
  bool _didInitListeners = false;

  @override
  void initState() {
    super.initState();

    _initTts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

        setState(() {
          _logPointPerMeterController.text = SettingsService().settings!.logPointPerMeter.toString();
          _rebateValueController.text = SettingsService().settings!.rebateValuePerLiter.toString();
        });
      //});
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
            ],
          ),
        );
      }
    );
  }
}
