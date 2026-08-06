import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class SettingsPage extends StatefulWidget {
  final String userId;

  const SettingsPage({
    super.key,
    required this.userId,
  });

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> with TickerProviderStateMixin {
  bool isLoading = true;
  TabController? _tabControllerServers;

  final TextEditingController _controllerLogPointPerM = TextEditingController();
  final TextEditingController _controllerRebateValue = TextEditingController();
  final TextEditingController _controllerDieselPrice = TextEditingController();
  final FocusNode _focusNodeLogPointPerM = FocusNode();
  final FocusNode _focusNodeRebateValue = FocusNode();
  final FocusNode _focusNodeDieselPrice = FocusNode();
  final FlutterTts _flutterTts = FlutterTts();

  final Map<String, Map<String, dynamic>> mapServerData = {};
  List<DocumentSnapshot<Map<String, dynamic>>> lstServerData = [];
  bool _controllersInitialized = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _fetchServers();
  }

  @override
  void dispose() {
    _controllerRebateValue.dispose();
    _controllerLogPointPerM.dispose();
    _controllerDieselPrice.dispose();
    _focusNodeLogPointPerM.dispose();
    _focusNodeRebateValue.dispose();
    _focusNodeDieselPrice.dispose();
    _flutterTts.stop();
    _tabControllerServers?.dispose();

    if (!kIsWeb) {
      FlutterBluePlus.stopScan();
    }
    super.dispose();
  }

  void _ensureControllersInitialized(SettingsService settings) {
    if (_controllersInitialized || settings.fireSettings == null) return;

    _controllerRebateValue.text =
        settings.fireSettings!.rebateValuePerLiter.toString();
    _controllerDieselPrice.text =
        settings.fireSettings!.dieselPrice.toString();
    _controllerLogPointPerM.text =
        settings.fireSettings!.logPointPerMeter.toString();
    _controllersInitialized = true;
  }

  Future<void> _saveGpsCheckInterval(SettingsService settings) async {
    if (settings.fireSettings == null) return;

    final log = int.tryParse(_controllerLogPointPerM.text.trim());
    if (log == null || log <= 0) {
      MyGlobalSnackBar.show('Enter a valid GPS check interval in meters');
      _controllerLogPointPerM.text =
          settings.fireSettings!.logPointPerMeter.toString();
      return;
    }
    if (log == settings.fireSettings!.logPointPerMeter) return;

    await settings.updateFireSettingsFields({settingLogPointPerMeter: log});
    if (mounted) MyGlobalSnackBar.show('Saved');
  }

  Future<void> _saveRebateValue(SettingsService settings) async {
    if (settings.fireSettings == null) return;

    final rebate = double.tryParse(_controllerRebateValue.text.trim());
    if (rebate == null) {
      MyGlobalSnackBar.show('Enter a valid rebate value');
      _controllerRebateValue.text =
          settings.fireSettings!.rebateValuePerLiter.toString();
      return;
    }
    if (rebate == settings.fireSettings!.rebateValuePerLiter) return;

    await settings.updateFireSettingsFields({settingRebateValue: rebate});
    if (mounted) MyGlobalSnackBar.show('Saved');
  }

  Future<void> _saveDieselPrice(SettingsService settings) async {
    if (settings.fireSettings == null) return;

    final dieselPrice = double.tryParse(_controllerDieselPrice.text.trim());
    if (dieselPrice == null || dieselPrice <= 0) {
      MyGlobalSnackBar.show('Enter a valid diesel price');
      _controllerDieselPrice.text =
          settings.fireSettings!.dieselPrice.toString();
      return;
    }
    if (dieselPrice == settings.fireSettings!.dieselPrice) return;

    await settings.updateFireSettingsFields({settingDieselPrice: dieselPrice});
    if (mounted) MyGlobalSnackBar.show('Saved');
  }

  Future<void> _saveVoicePrompt(SettingsService settings, bool value) async {
    if (settings.fireSettings == null) return;
    if (value == settings.fireSettings!.isVoicePromptOn) return;

    await settings.updateFireSettingsFields({
      settingIsVoicePromptOn: value,
    });
    if (!mounted) return;
    MyGlobalSnackBar.show('Saved');
    if (value) {
      _flutterTts.speak('Voice Prompt enabled');
    }
  }

  void _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _fetchServers() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection(collectionUsers)
          .doc(uid)
          .collection(collectionBaseStations)
          .get();

      if (!mounted) return;
      setState(() {
        lstServerData = snapshot.docs;
        mapServerData.clear();

        for (final doc in lstServerData) {
          mapServerData[doc.id] = doc.data() ?? {};
          printDebugMsg('Server Data: ${jsonEncode(doc.data() ?? {})}');
        }

        if (lstServerData.isNotEmpty) {
          _tabControllerServers?.dispose();
          _tabControllerServers = TabController(
            length: lstServerData.length,
            vsync: this,
          );
        }

        isLoading = false;
      });
    } catch (e) {
      MyGlobalSnackBar.show('Load Server Data Failed: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _fieldDescription(String text) {
    return Text(
      text,
      softWrap: true,
      style: const TextStyle(
        fontSize: 12,
        color: Colors.white54,
        fontFamily: 'Poppins',
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        color: Colors.white,
        fontFamily: 'Poppins',
      ),
    );
  }

  Widget _buildGeneralTab(SettingsService settings) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: MyTextHeader(
            text: 'Tracking',
            color: Colors.white,
            fontsize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldDescription(
                'Minimum distance (meters) before GPS checks for geofence '
                'crossings during tracking. Lower values update more often but '
                'use more battery.\n\n'
                'Suggested: 10 m (balanced), 25 m (longer battery life), '
                '50 m (best battery, less precise).',
              ),
              const SizedBox(height: 6),
              _fieldLabel('GPS Check Interval'),
              const SizedBox(height: 2),
              MyTextFormField(
                focusNode: _focusNodeLogPointPerM,
                backgroundColor: colorAppBackground,
                foregroundColor: Colors.white,
                controller: _controllerLogPointPerM,
                hintText: 'Enter value here',
                suffix: 'm',
                inputType: TextInputType.number,
                showLine: true,
                onFocusLost: () => _saveGpsCheckInterval(settings),
                onFieldSubmitted: (_) => _saveGpsCheckInterval(settings),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldDescription(
                'Rebate amount per kilometer traveled.',
              ),
              const SizedBox(height: 6),
              _fieldLabel('Rebate Value'),
              const SizedBox(height: 2),
              MyTextFormField(
                focusNode: _focusNodeRebateValue,
                backgroundColor: colorAppBackground,
                foregroundColor: Colors.white,
                controller: _controllerRebateValue,
                hintText: 'Enter value here',
                suffix: 'R/km',
                inputType: const TextInputType.numberWithOptions(decimal: true),
                showLine: true,
                onFocusLost: () => _saveRebateValue(settings),
                onFieldSubmitted: (_) => _saveRebateValue(settings),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldDescription(
                'Current diesel pump price used to estimate fuel cost inside geofences.',
              ),
              const SizedBox(height: 6),
              _fieldLabel('Diesel Price'),
              const SizedBox(height: 2),
              MyTextFormField(
                focusNode: _focusNodeDieselPrice,
                backgroundColor: colorAppBackground,
                foregroundColor: Colors.white,
                controller: _controllerDieselPrice,
                hintText: 'Enter value here',
                suffix: 'R/L',
                inputType: const TextInputType.numberWithOptions(decimal: true),
                showLine: true,
                onFocusLost: () => _saveDieselPrice(settings),
                onFieldSubmitted: (_) => _saveDieselPrice(settings),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: MyTextHeader(
            text: 'Voice',
            color: Colors.white,
            fontsize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldDescription(
                'Spoken feedback during tracking and geofence events.',
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: _fieldLabel('Voice Prompt'),
                value: settings.fireSettings!.isVoicePromptOn,
                activeThumbColor: Colors.white,
                activeTrackColor: colorOrange,
                onChanged: (value) => _saveVoicePrompt(settings, value),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildServersTab() {
    if (lstServerData.isEmpty) {
      return myCenterMsg('No base stations configured');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabControllerServers,
          isScrollable: true,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: lstServerData.map((doc) {
            final name = doc.data()?['name']?.toString() ?? 'Station';
            return Tab(text: name);
          }).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabControllerServers,
            children: lstServerData.map((doc) {
              final data = doc.data() ?? {};
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
                children: [
                  const MyTextHeader(text: 'Base Station', fontsize: 16),
                  const SizedBox(height: 12),
                  _settingsInfoRow('Name', '${data['name'] ?? '—'}'),
                  _settingsInfoRow('Device ID', doc.id),
                  if (data['ip'] != null)
                    _settingsInfoRow('IP', '${data['ip']}'),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _settingsInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitorsTab() {
    return myCenterMsg('Monitor map settings coming soon');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        if (settings.isLoading || isLoading) {
          return Scaffold(
            backgroundColor: colorAppBackground,
            body: Center(child: myProgressCircle()),
          );
        }

        _ensureControllersInitialized(settings);

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: colorAppBackground,
            appBar: AppBar(
              backgroundColor: colorAppBar,
              foregroundColor: Colors.white,
              title: myAppbarTitle('Settings'),
              bottom: const TabBar(
                indicatorColor: Colors.blueAccent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                tabs: [
                  Tab(text: 'General'),
                  Tab(text: 'Servers'),
                  Tab(text: 'Monitors'),
                ],
              ),
            ),
            body: settings.fireSettings == null
                ? myCenterMsg('Settings not available')
                : TabBarView(
                    children: [
                      _buildGeneralTab(settings),
                      _buildServersTab(),
                      _buildMonitorsTab(),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
