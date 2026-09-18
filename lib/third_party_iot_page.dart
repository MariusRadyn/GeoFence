import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/login_page.dart';
import 'package:geofence/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Free SONOFF / eWeLink control via CoolKit V2 OAuth + Cloud Functions.
/// Embed in IoT Devices with [embedded] = true (no outer Scaffold).
class SonoffIotPanel extends StatefulWidget {
  const SonoffIotPanel({
    super.key,
    this.embedded = false,
    this.active = true,
    this.onRemoved,
  });

  final bool embedded;

  /// When embedded in a TabBarView, only bootstrap while this tab is selected.
  final bool active;

  /// Called after SONOFF is deleted and eWeLink is unlinked (hide tab, etc.).
  final VoidCallback? onRemoved;

  @override
  State<SonoffIotPanel> createState() => _SonoffIotPanelState();
}

/// Standalone route kept for deep links / What's New.
class ThirdPartyIotPage extends StatelessWidget {
  const ThirdPartyIotPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SonoffIotPanel(embedded: false);
  }
}

class _SonoffIotPanelState extends State<SonoffIotPanel>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: cloudFunctionsRegion);

  bool _loading = true;
  bool _busy = false;
  bool _awaitingOAuth = false;
  bool _awaitingPairing = false;
  bool _oauthCheckInFlight = false;
  bool _linked = false;
  bool _bootstrapped = false;
  DateTime? _oauthStartedAt;
  Timer? _oauthPollTimer;
  String? _linkedEmail;
  String? _linkedRegion;
  List<_SonoffDevice> _devices = [];
  Map<String, String> _customNames = {};
  String? _error;
  String _statusTitle = 'Opening SONOFF';
  String _statusBody = 'Getting ready…';

  @override
  bool get wantKeepAlive => true;

  void _setStatus(String title, String body) {
    if (!mounted) return;
    setState(() {
      _statusTitle = title;
      _statusBody = body;
    });
  }

  String get _uid =>
      currentDataOwnerUid() ?? 'guest';

  String get _namesPrefsKey => 'ewelink_device_names_$_uid';
  String get _checkedPrefsKey => 'ewelink_link_checked_$_uid';
  String get _linkedPrefsKey => 'ewelink_linked_$_uid';
  String get _emailPrefsKey => 'ewelink_email_$_uid';
  String get _regionPrefsKey => 'ewelink_region_$_uid';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.embedded || widget.active) {
      _bootstrapIfNeeded();
    } else {
      _loading = false;
      _statusTitle = 'SONOFF';
      _statusBody = 'Open this tab to manage eWeLink devices.';
    }
  }

  @override
  void didUpdateWidget(covariant SonoffIotPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _bootstrapIfNeeded();
      if (_awaitingOAuth) {
        _checkOAuthLinked();
      }
    }
  }

  @override
  void dispose() {
    _stopOAuthPoll();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_awaitingOAuth) {
      // Do not clear _awaitingOAuth here — browser open often causes an early
      // resume before the user has finished linking.
      _checkOAuthLinked();
      return;
    }
    if (_awaitingPairing) {
      _awaitingPairing = false;
      if (_linked) {
        _refreshDevices();
      }
    }
  }

  void _startOAuthPoll() {
    _oauthPollTimer?.cancel();
    _oauthPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkOAuthLinked();
    });
  }

  void _stopOAuthPoll() {
    _oauthPollTimer?.cancel();
    _oauthPollTimer = null;
  }

  /// Polls until eWeLink is linked, then refreshes devices.
  Future<void> _checkOAuthLinked() async {
    if (!_awaitingOAuth || _oauthCheckInFlight || !mounted) return;
    final started = _oauthStartedAt;
    if (started != null &&
        DateTime.now().difference(started) < const Duration(seconds: 3)) {
      // Ignore the resume blip when the browser first opens.
      return;
    }
    // Give up after 3 minutes of waiting.
    if (started != null &&
        DateTime.now().difference(started) > const Duration(minutes: 3)) {
      _awaitingOAuth = false;
      _stopOAuthPoll();
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
        _setStatus(
          'Ready to link',
          'Linking timed out. Tap Link with eWeLink again after finishing login.',
        );
      }
      return;
    }

    _oauthCheckInFlight = true;
    try {
      final status = await _call('ewelinkGetStatus');
      final linked = status['linked'] == true;
      if (!linked || !mounted) return;

      _awaitingOAuth = false;
      _stopOAuthPoll();

      final email = status['email'] as String?;
      final region = status['region'] as String?;
      setState(() {
        _linked = true;
        _linkedEmail = email;
        _linkedRegion = region;
        _bootstrapped = true;
        _busy = true;
        _loading = true;
        _error = null;
        _statusTitle = 'Loading devices';
        _statusBody = 'eWeLink linked — fetching your SONOFF devices…';
      });
      await _persistLinkStatus(
        linked: true,
        email: email,
        region: region,
      );
      await _loadCustomNames();
      await _refreshDevices(showSpinner: false);
      if (mounted) {
        MyGlobalSnackBar.show('eWeLink linked — devices refreshed');
      }
    } catch (e) {
      printDebugMsg('OAuth link check failed: $e');
    } finally {
      _oauthCheckInFlight = false;
      if (mounted && !_awaitingOAuth) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _bootstrapIfNeeded() async {
    if (_bootstrapped) return;
    await _bootstrap();
  }

  Future<void> _persistLinkStatus({
    required bool linked,
    String? email,
    String? region,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      await prefs.setBool(_checkedPrefsKey, true);
      await prefs.setBool(_linkedPrefsKey, linked);
      if (email != null && email.isNotEmpty) {
        await prefs.setString(_emailPrefsKey, email);
      } else if (!linked) {
        await prefs.remove(_emailPrefsKey);
      }
      if (region != null && region.isNotEmpty) {
        await prefs.setString(_regionPrefsKey, region);
      } else if (!linked) {
        await prefs.remove(_regionPrefsKey);
      }
    } catch (e) {
      printDebugMsg('Persist eWeLink link status failed: $e');
    }
  }

  Future<({bool checked, bool linked, String? email, String? region})>
      _loadCachedLinkStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      return (
        checked: prefs.getBool(_checkedPrefsKey) == true,
        linked: prefs.getBool(_linkedPrefsKey) == true,
        email: prefs.getString(_emailPrefsKey),
        region: prefs.getString(_regionPrefsKey),
      );
    } catch (_) {
      return (checked: false, linked: false, email: null, region: null);
    }
  }

  Future<void> _loadCustomNames() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      final raw = prefs.getString(_namesPrefsKey);
      if (raw == null || raw.isEmpty) {
        _customNames = {};
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _customNames = decoded.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      }
    } catch (e) {
      printDebugMsg('Load custom device names failed: $e');
      _customNames = {};
    }
  }

  Future<void> _saveCustomNames() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      await prefs
          .setString(_namesPrefsKey, jsonEncode(_customNames))
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      printDebugMsg('Save custom device names failed: $e');
      rethrow;
    }
  }

  void _applyCustomNames(List<_SonoffDevice> list) {
    for (final device in list) {
      final custom = _customNames[device.deviceId]?.trim();
      if (custom != null && custom.isNotEmpty) {
        device.name = custom;
      } else {
        device.name = device.ewelinkName;
      }
    }
  }

  Future<void> _editDeviceName(_SonoffDevice device) async {
    final controller = TextEditingController(text: device.name);
    final saved = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colorAppTitle,
          title: const Text(
            'Device name',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: device.ewelinkName,
              hintStyle: const TextStyle(color: Colors.white38),
              helperText: 'Custom display name for this device',
              helperStyle: const TextStyle(color: Colors.white54),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white38),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colorBlue),
              ),
            ),
            onSubmitted: (v) {
              final nav = Navigator.of(ctx);
              if (nav.canPop()) nav.pop(v.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                final nav = Navigator.of(ctx);
                if (nav.canPop()) nav.pop();
              },
              style: TextButton.styleFrom(foregroundColor: colorBlue),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                final nav = Navigator.of(ctx);
                if (nav.canPop()) nav.pop(controller.text.trim());
              },
              style: TextButton.styleFrom(foregroundColor: colorBlue),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    // Dispose after the dialog route has finished closing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (saved == null || !mounted) return;

    setState(() {
      if (saved.isEmpty || saved == device.ewelinkName) {
        _customNames.remove(device.deviceId);
        device.name = device.ewelinkName;
      } else {
        _customNames[device.deviceId] = saved;
        device.name = saved;
      }
    });

    try {
      await _saveCustomNames();
      if (!mounted) return;
      MyGlobalSnackBar.show('Device name saved');
    } catch (_) {
      if (!mounted) return;
      MyGlobalSnackBar.show('Name updated, but could not save permanently');
    }
  }

  Future<void> _bootstrap({bool forceStatusCheck = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _bootstrapped = true;
        _error = 'Sign in to Limitless first, then link your eWeLink account.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _statusTitle = 'Checking eWeLink link';
      _statusBody =
          'Contacting Limitless servers to see if your eWeLink account is already linked…';
    });

    try {
      await _loadCustomNames();

      if (!forceStatusCheck) {
        final cached = await _loadCachedLinkStatus();
        if (cached.checked) {
          if (!mounted) return;
          setState(() {
            _linked = cached.linked;
            _linkedEmail = cached.email;
            _linkedRegion = cached.region;
            _bootstrapped = true;
          });
          if (cached.linked) {
            _setStatus(
              'Loading devices',
              'Fetching your SONOFF / eWeLink devices. This can take a few seconds…',
            );
            await _refreshDevices(showSpinner: false);
          } else {
            _setStatus(
              'Ready to link',
              'No eWeLink account is linked yet.',
            );
          }
          return;
        }
      }

      _setStatus(
        'Checking eWeLink link',
        'Verifying your account status with eWeLink…',
      );
      final status = await _call('ewelinkGetStatus');
      final linked = status['linked'] == true;
      final email = status['email'] as String?;
      final region = status['region'] as String?;
      if (!mounted) return;
      setState(() {
        _linked = linked;
        _linkedEmail = email;
        _linkedRegion = region;
        _bootstrapped = true;
      });
      await _persistLinkStatus(
        linked: linked,
        email: email,
        region: region,
      );
      if (linked) {
        _setStatus(
          'Loading devices',
          'Fetching your SONOFF / eWeLink devices. This can take a few seconds…',
        );
        await _refreshDevices(showSpinner: false);
      } else {
        _setStatus(
          'Ready to link',
          'No eWeLink account is linked yet.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _bootstrapped = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    final callable = _functions.httpsCallable(name);
    final result = await callable.call(data ?? <String, dynamic>{});
    final payload = result.data;
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    return <String, dynamic>{};
  }

  String _friendlyError(Object e) {
    String raw;
    if (e is FirebaseFunctionsException) {
      raw = e.message?.trim().isNotEmpty == true
          ? e.message!
          : 'Request failed (${e.code}).';
    } else {
      raw = e.toString();
    }
    // CoolKit sometimes returns Chinese; never show CJK to the user.
    if (RegExp(r'[\u3400-\u9FFF]').hasMatch(raw)) {
      final codeMatch = RegExp(r'\b(\d{3,5})\b').firstMatch(raw);
      final code = codeMatch?.group(1);
      return code == null
          ? 'eWeLink request failed.'
          : 'eWeLink request failed (code $code).';
    }
    return raw;
  }

  Future<void> _openLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (!mounted) return;
    await _bootstrap(forceStatusCheck: true);
  }

  Future<void> _startOAuth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _openLogin();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _statusTitle = 'Opening eWeLink';
      _statusBody =
          'Preparing the secure eWeLink login page in your browser…';
    });

    try {
      final result = await _call('ewelinkStartOAuth', {'region': 'eu'});
      final url = '${result['url'] ?? ''}';
      if (url.isEmpty) {
        throw Exception('No OAuth URL returned from server.');
      }
      final uri = Uri.parse(url);
      _awaitingOAuth = true;
      _oauthStartedAt = DateTime.now();
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        _awaitingOAuth = false;
        _oauthStartedAt = null;
        throw Exception('Could not open eWeLink login page.');
      }
      if (!mounted) return;
      setState(() {
        _busy = true;
        _loading = true;
        _statusTitle = 'Waiting for eWeLink';
        _statusBody =
            'Finish login in the browser. This screen will update automatically when linked.';
      });
      _startOAuthPoll();
      MyGlobalSnackBar.show(
        'Complete login in the browser — this screen will refresh automatically.',
      );
    } catch (e) {
      _awaitingOAuth = false;
      _oauthStartedAt = null;
      _stopOAuthPoll();
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _busy = false;
        _loading = false;
      });
      MyGlobalMessage.show(
        'Link failed',
        _friendlyError(e),
        MyMessageType.error,
      );
    }
  }

  String get _sonoffTabPrefsKey => 'sonoff_tab_enabled_$_uid';

  Future<void> _unlinkAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorAppTitle,
        title: const Text(
          'Unlink eWeLink?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Your SONOFF devices will no longer be controllable from Limitless.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: colorBlue),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: colorBlue),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _performUnlink(showSnackBar: true);
  }

  Future<void> _deleteSonoff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorAppTitle,
        title: const Text(
          'Delete SONOFF?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          _linked
              ? 'This will unlink your eWeLink account and remove the SONOFF tab.'
              : 'This will remove the SONOFF tab from iOT Devices.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: colorBlue),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_linked) {
        await _call('ewelinkUnlinkAccount');
      }
      await _persistLinkStatus(linked: false);
      try {
        final prefs = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 2));
        await prefs
            .setBool(_sonoffTabPrefsKey, false)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _linked = false;
        _linkedEmail = null;
        _linkedRegion = null;
        _devices = [];
      });
      MyGlobalSnackBar.show('SONOFF removed');
      widget.onRemoved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
      MyGlobalMessage.show(
        'Delete failed',
        _friendlyError(e),
        MyMessageType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _performUnlink({required bool showSnackBar}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _call('ewelinkUnlinkAccount');
      await _persistLinkStatus(linked: false);
      if (!mounted) return;
      setState(() {
        _linked = false;
        _linkedEmail = null;
        _linkedRegion = null;
        _devices = [];
      });
      if (showSnackBar) {
        MyGlobalSnackBar.show('eWeLink account unlinked');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshDevices({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _busy = true;
        _error = null;
        _statusTitle = 'Refreshing devices';
        _statusBody =
            'Fetching the latest SONOFF / eWeLink device list…';
      });
    }
    try {
      final result = await _call('ewelinkListDevices');
      final raw = result['devices'];
      final list = <_SonoffDevice>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            list.add(_SonoffDevice.fromMap(Map<String, dynamic>.from(item)));
          }
        }
      }
      if (!mounted) return;
      _applyCustomNames(list);
      setState(() {
        _linked = true;
        _linkedEmail = result['email'] as String? ?? _linkedEmail;
        _linkedRegion = result['region'] as String? ?? _linkedRegion;
        _devices = list;
      });
      await _persistLinkStatus(
        linked: true,
        email: _linkedEmail,
        region: _linkedRegion,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted && showSpinner) setState(() => _busy = false);
    }
  }

  Future<void> _openEweLinkForPairing() async {
    // Prefer opening the installed eWeLink app; fall back to Play Store / web.
    final candidates = <Uri>[
      Uri.parse('ewelink://'),
      Uri.parse('market://details?id=com.coolkit'),
      Uri.parse(
        'https://play.google.com/store/apps/details?id=com.coolkit',
      ),
      Uri.parse('https://www.ewelink.cc/en/'),
    ];

    _awaitingPairing = true;
    for (final uri in candidates) {
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) {
          if (!mounted) return;
          MyGlobalSnackBar.show(
            'Pair the device in eWeLink, then return here to refresh.',
          );
          return;
        }
      } catch (_) {
        // Try next candidate.
      }
    }
    _awaitingPairing = false;
    if (!mounted) return;
    MyGlobalMessage.show(
      'eWeLink app',
      'Could not open eWeLink. Install it from the Play Store, pair your device there, then return and pull to refresh.',
      MyMessageType.warning,
    );
  }

  Future<void> _showPairDeviceSheet() async {
    if (!_linked) {
      MyGlobalSnackBar.show('Link your eWeLink account first');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colorAppTitle,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pair a SONOFF device',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Limitless controls devices after they are added to your eWeLink account. '
                  'Pairing (Wi‑Fi / Bluetooth setup) is done in the eWeLink app.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 16),
                const _PairStep(
                  number: '1',
                  text:
                      'Put the relay into pairing mode (usually press and hold until the LED blinks fast).',
                ),
                const _PairStep(
                  number: '2',
                  text:
                      'Open eWeLink → Add Device, and complete Wi‑Fi pairing with the same account you linked here.',
                ),
                const _PairStep(
                  number: '3',
                  text:
                      'Return to Limitless. We will refresh your device list automatically.',
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openEweLinkForPairing();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.link),
                    label: const Text('Open eWeLink to pair'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _refreshDevices();
                    },
                    style: TextButton.styleFrom(foregroundColor: colorBlue),
                    child: const Text('I already paired — refresh list'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _setPower(
    _SonoffDevice device,
    bool on, {
    int channel = 1,
  }) async {
    setState(() {
      device.pending = true;
      _error = null;
    });
    try {
      final result = await _call('ewelinkSetDevicePower', {
        'deviceId': device.deviceId,
        'state': on ? 'on' : 'off',
        'channel': channel,
        'itemType': device.itemType,
        'hasSwitches': device.usesSwitchesProtocol ||
            (device.switches != null && device.switches!.isNotEmpty),
        'usesSwitchesProtocol': device.usesSwitchesProtocol,
      });
      if (!mounted) return;
      final newState = '${result['state'] ?? (on ? 'on' : 'off')}';
      setState(() {
        if (device.switches != null && device.switches!.isNotEmpty) {
          final idx = channel - 1;
          if (idx >= 0 && idx < device.switches!.length) {
            device.switches![idx] =
                Map<String, dynamic>.from(device.switches![idx])
                  ..['switch'] = newState;
          }
          device.state = device.switches!.first['switch']?.toString();
        } else {
          device.state = newState;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
      MyGlobalSnackBar.show(_friendlyError(e));
    } finally {
      if (mounted) setState(() => device.pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final signedIn = FirebaseAuth.instance.currentUser != null;

    final body = _loading
        ? _StatusScreen(title: _statusTitle, body: _statusBody)
        : RefreshIndicator(
            onRefresh: () async {
              if (_linked) {
                await _refreshDevices();
              } else {
                await _bootstrap(forceStatusCheck: true);
              }
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (!signedIn) ...[
                  _InfoCard(
                    title: 'Sign in required',
                    body:
                        'Sign in to Limitless IOT, then link your eWeLink account to control SONOFF devices.',
                    actionLabel: 'Sign in',
                    onAction: _openLogin,
                  ),
                ] else if (!_linked) ...[
                  _InfoCard(
                    title: 'Link eWeLink account',
                    body:
                        'SONOFF devices are linked through your eWeLink account. '
                        'Tap below to sign in securely on the official eWeLink authorization page '
                        '(South Africa / Europe). After linking, return here and pull to refresh.',
                    actionLabel: _busy ? 'Opening…' : 'Link with eWeLink',
                    onAction: _busy ? null : _startOAuth,
                  ),
                ] else ...[
                  _LinkedHeader(
                    email: _linkedEmail ?? 'eWeLink account',
                    region: _linkedRegion ?? 'eu',
                    busy: _busy,
                    onUnlink: _unlinkAccount,
                    onPair: _showPairDeviceSheet,
                  ),
                  const SizedBox(height: 12),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _StatusCard(
                        title: _statusTitle,
                        body: _statusBody,
                      ),
                    ),
                  if (_devices.isEmpty && !_busy)
                    _InfoCard(
                      title: 'No devices found',
                      body:
                          'Pair a SONOFF relay in the eWeLink app first (same account you linked here), then refresh.',
                      actionLabel: 'Pair device',
                      onAction: _showPairDeviceSheet,
                    )
                  else if (!_busy)
                    ..._devices.map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _DeviceTile(
                          device: d,
                          onChanged: (on) => _setPower(d, on),
                          onChannelChanged: (channel, on) =>
                              _setPower(d, on, channel: channel),
                          onRename: () => _editDeviceName(d),
                        ),
                      ),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          );

    if (widget.embedded) {
      return ColoredBox(
        color: colorAppBackground,
        child: Stack(
          children: [
            Column(
              children: [
                if (_linked && !_loading)
                  Material(
                    color: colorAppBar,
                    child: Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          tooltip: 'Pair device',
                          onPressed: _busy ? null : _showPairDeviceSheet,
                          icon: const Icon(Icons.add_link, color: Colors.white),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: _busy ? null : () => _refreshDevices(),
                          icon: const Icon(Icons.refresh, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: body),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'sonoffDeleteFab',
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                tooltip: 'Delete SONOFF',
                onPressed: _busy || _loading ? null : _deleteSonoff,
                child: const Icon(Icons.delete_outline),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        title: myAppbarTitle('SONOFF'),
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        actions: [
          if (_linked) ...[
            IconButton(
              tooltip: 'Pair device',
              onPressed: _busy ? null : _showPairDeviceSheet,
              icon: const Icon(Icons.add_link),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : () => _refreshDevices(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'sonoffDeleteFabStandalone',
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        tooltip: 'Delete SONOFF',
        onPressed: _busy || _loading ? null : _deleteSonoff,
        child: const Icon(Icons.delete_outline),
      ),
      body: body,
    );
  }
}

class _StatusScreen extends StatelessWidget {
  const _StatusScreen({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _StatusCard(title: title, body: body),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorTile,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.blue,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _SonoffDevice {
  _SonoffDevice({
    required this.deviceId,
    required this.ewelinkName,
    required this.name,
    required this.online,
    required this.productModel,
    required this.brandName,
    required this.itemType,
    required this.channelCount,
    required this.usesSwitchesProtocol,
    required this.state,
    required this.switches,
  });

  final String deviceId;
  final String ewelinkName;
  String name;
  final bool online;
  final String productModel;
  final String brandName;
  final int itemType;
  final int channelCount;
  final bool usesSwitchesProtocol;
  String? state;
  final List<Map<String, dynamic>>? switches;
  bool pending = false;

  bool get isOn => state == 'on';
  bool get hasCustomName =>
      name.trim().isNotEmpty && name.trim() != ewelinkName.trim();

  factory _SonoffDevice.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>>? switches;
    final raw = map['switches'];
    if (raw is List) {
      switches = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    final ewelinkName = '${map['name'] ?? 'Device'}';
    return _SonoffDevice(
      deviceId: '${map['deviceId'] ?? ''}',
      ewelinkName: ewelinkName,
      name: ewelinkName,
      online: map['online'] == true,
      productModel: '${map['productModel'] ?? ''}',
      brandName: '${map['brandName'] ?? 'SONOFF'}',
      itemType: map['itemType'] is num ? (map['itemType'] as num).toInt() : 1,
      channelCount:
          map['channelCount'] is num ? (map['channelCount'] as num).toInt() : 1,
      usesSwitchesProtocol: map['usesSwitchesProtocol'] == true,
      state: map['state']?.toString(),
      switches: switches,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: colorOrange.withValues(alpha: 0.55),
                disabledForegroundColor: Colors.white,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _PairStep extends StatelessWidget {
  const _PairStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorOrange.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedHeader extends StatelessWidget {
  const _LinkedHeader({
    required this.email,
    required this.region,
    required this.busy,
    required this.onUnlink,
    required this.onPair,
  });

  final String email;
  final String region;
  final bool busy;
  final VoidCallback onUnlink;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.link, color: Colors.lightGreenAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Region: $region',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: busy ? null : onUnlink,
                style: TextButton.styleFrom(foregroundColor: colorBlue),
                child: const Text('Unlink'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onPair,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: colorOrange.withValues(alpha: 0.8)),
              ),
              icon: const Icon(Icons.add_link),
              label: const Text('Pair device'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.onChanged,
    required this.onChannelChanged,
    required this.onRename,
  });

  final _SonoffDevice device;
  final ValueChanged<bool> onChanged;
  final void Function(int channel, bool on) onChannelChanged;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final multi =
        device.channelCount > 1 &&
        device.switches != null &&
        device.switches!.length > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorTile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                device.online ? Icons.power : Icons.power_off,
                color: device.online ? Colors.lightGreenAccent : Colors.white38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: onRename,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit,
                            size: 16,
                            color: colorBlue.withValues(alpha: 0.9),
                          ),
                        ],
                      ),
                      Text(
                        [
                          if (device.hasCustomName) device.ewelinkName,
                          if (device.brandName.isNotEmpty) device.brandName,
                          if (device.productModel.isNotEmpty)
                            device.productModel,
                        ].join(' · '),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      if (!device.online)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Relay is offline',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'Online',
                            style: TextStyle(
                              color: Colors.lightGreenAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!multi)
                Switch(
                  value: device.isOn,
                  onChanged: (!device.online || device.pending)
                      ? null
                      : onChanged,
                ),
              if (device.pending)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (multi) ...[
            const SizedBox(height: 8),
            ...device.switches!.asMap().entries.map((entry) {
              final channel = (entry.value['outlet'] is num)
                  ? (entry.value['outlet'] as num).toInt() + 1
                  : entry.key + 1;
              final on = entry.value['switch']?.toString() == 'on';
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Channel $channel',
                  style: const TextStyle(color: Colors.white),
                ),
                value: on,
                onChanged: (!device.online || device.pending)
                    ? null
                    : (v) => onChannelChanged(channel, v),
              );
            }),
          ],
        ],
      ),
    );
  }
}
