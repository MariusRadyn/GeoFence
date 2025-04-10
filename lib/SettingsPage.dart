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
  final FlutterTts _flutterTts = FlutterTts();
  bool _didInitListeners = false;

  @override
  void initState() {
    super.initState();

    _initTts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // This executes after the first frame is built, when context is fully valid
      if (!mounted) return;

      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

      settingsProvider.LoadSettings(widget.userId).then((_) {
        if (!mounted) return;

        setState(() {
          _logPointPerMeterController.text = settingsProvider.LogPointPerMeter.toString();
        });
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!mounted) return;

    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    // You could set up listeners here or perform one-time operations
    // that depend on inherited widgets
    if (!_didInitListeners) {
      settingsProvider.addListener(_updateControllerValues);
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
      Provider.of<SettingsProvider>(context, listen: false)
          .removeListener(_updateControllerValues);
    }

    super.dispose();
  }

// Method to update controller values
  void _updateControllerValues() {
    if(!mounted) return;

    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    if (!settingsProvider.isLoading && mounted) {
      setState(() {
        _logPointPerMeterController.text = (settingsProvider.LogPointPerMeter).toString();
      });
    }
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

    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {

        if (settingsProvider.isLoading) {
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
                   settingsProvider.UpdateSetting(
                       widget.userId, SettingLogPointPerMeter,
                       _logPointPerMeterController.text);

                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved")));
                 },
              ),
            ],
          ),
          body: ListView(

            children: [
              const SizedBox(height: 20),

              MyTextOption(
                controller: _logPointPerMeterController,
                label: 'Log Location Interval',
                description: "Record a map location everytime you move this far in meters",
              ),

              const SizedBox(height: 10),

              // isVoicePromptOn
              MyToggleOption(
                  value: settingsProvider.IsVoicePromptOn,
                  label: 'Voice Prompt',
                  subtitle: 'Allow me to give you vocal feedback',
                  onChanged: (bool value)=>
                  {
                    //setState(() {
                    //  _isVoicePromptOn = value;
                    //}),

                    settingsProvider.UpdateSetting(
                        widget.userId, SettingIsVoicePromptOn, value),

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
