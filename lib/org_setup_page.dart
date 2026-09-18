import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';

class OrgSetupPage extends StatefulWidget {
  const OrgSetupPage({super.key});

  @override
  State<OrgSetupPage> createState() => _OrgSetupPageState();
}

class _OrgSetupPageState extends State<OrgSetupPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _busy = false;
  /// null = choose, false = create, true = join
  bool? _joinMode;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      MyGlobalMessage.show(
        'Name required',
        'Enter a name for your profile.',
        MyMessageType.info,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<OrgService>().createOrganization(name);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      MyGlobalMessage.show('Create failed', '$e', MyMessageType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      MyGlobalMessage.show(
        'Code required',
        'Enter the join code from your Admin.',
        MyMessageType.info,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<OrgService>().acceptInvite(code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (e) {
      MyGlobalMessage.show(
        'Join failed',
        e.message ?? e.code,
        MyMessageType.error,
      );
    } catch (e) {
      MyGlobalMessage.show('Join failed', '$e', MyMessageType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colorAppBackground,
        appBar: AppBar(
          backgroundColor: colorAppBar,
          foregroundColor: Colors.white,
          title: myAppbarTitle('Profile'),
          automaticallyImplyLeading: false,
        ),
        body: _busy
            ? myProgressCircle()
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const MyText(
                    text:
                        'Create your own profile as Admin, or join an existing one with an invite code.',
                    color: Colors.white70,
                    fontsize: 16,
                  ),
                  const SizedBox(height: 24),
                  if (_joinMode == null) ...[
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorOrange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: () => setState(() => _joinMode = false),
                      child: const Text('Create as Admin'),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: () => setState(() => _joinMode = true),
                      child: const Text('I have a join code'),
                    ),
                  ] else if (_joinMode == false) ...[
                    MyTextFormField(
                      controller: _nameController,
                      hintText: 'Profile name',
                      backgroundColor: colorAppTitle,
                      foregroundColor: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorOrange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _create,
                      child: const Text('Create as Admin'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _joinMode = null),
                      child: const Text(
                        'Back',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ] else ...[
                    MyTextFormField(
                      controller: _codeController,
                      hintText: 'Join code',
                      backgroundColor: colorAppTitle,
                      foregroundColor: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorOrange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _join,
                      child: const Text('Join profile'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _joinMode = null),
                      child: const Text(
                        'Back',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
