import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:geofence/utils.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

const String _orgInviteQrPrefix = 'LIMITLESS_ORG:';

String encodeOrgInviteQr(String code) =>
    '$_orgInviteQrPrefix${code.trim().toUpperCase()}';

String? decodeOrgInviteQr(String raw) {
  final t = raw.trim();
  final upper = t.toUpperCase();
  if (upper.startsWith(_orgInviteQrPrefix)) {
    final code = upper.substring(_orgInviteQrPrefix.length).trim();
    return code.isEmpty ? null : code;
  }
  final bare = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (bare.length >= 4 && bare.length <= 12) return bare;
  return null;
}

/// Organisations as tiles, with Invite / Join in the bottom bar (popups).
class OrganisationsPage extends StatefulWidget {
  const OrganisationsPage({super.key});

  @override
  State<OrganisationsPage> createState() => _OrganisationsPageState();
}

class _OrganisationsPageState extends State<OrganisationsPage>
    with SingleTickerProviderStateMixin {
  List<OrgMemberRow> _members = [];
  bool _loadingMembers = true;
  bool _switching = false;
  String? _teamOrgId;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOwnTeam();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Team always lists members linked to *your* owned profile — never another
  /// profile you merely joined.
  OrgMembership? _ownedMembership(OrgService org) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    for (final m in org.memberships) {
      if (m.orgId == uid || m.ownerUid == uid) return m;
    }
    return null;
  }

  bool _canManageOwnTeam(OrgService org) {
    final owned = _ownedMembership(org);
    return owned != null && owned.isAdmin;
  }

  Future<void> _loadOwnTeam() async {
    final org = context.read<OrgService>();
    final owned = _ownedMembership(org);
    await _loadTeamFor(owned?.orgId);
  }

  Future<void> _loadTeamFor(String? orgId) async {
    final id = (orgId ?? '').trim();
    if (id.isEmpty) {
      if (!mounted) return;
      setState(() {
        _members = [];
        _teamOrgId = null;
        _loadingMembers = false;
      });
      return;
    }

    setState(() {
      _loadingMembers = true;
      _teamOrgId = id;
      _members = [];
    });
    try {
      final list = await context.read<OrgService>().listMembers(orgId: id);
      if (!mounted) return;
      // Ignore stale responses if user switched again.
      if (_teamOrgId != id) return;
      setState(() {
        _members = list;
        _loadingMembers = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_teamOrgId != id) return;
      setState(() => _loadingMembers = false);
      MyGlobalMessage.show('Members', '$e', MyMessageType.error);
    }
  }

  Future<void> _switchOrg(String orgId) async {
    if (orgId.isEmpty) return;
    final org = context.read<OrgService>();
    OrgMembership? target;
    for (final m in org.memberships) {
      if (m.orgId == orgId) {
        target = m;
        break;
      }
    }

    if (org.orgId == orgId) {
      // Stay on this profile; refresh own team only (not the linked org's roster).
      await _loadOwnTeam();
      return;
    }

    setState(() => _switching = true);
    try {
      await org.switchOrganisation(orgId);
      if (!mounted) return;
      // Keep Team on your owned profile members — never swap to a linked roster.
      await _loadOwnTeam();
      if (!mounted) return;
      MyGlobalSnackBar.show(
        'Switched to ${org.membership?.displayName ?? target?.displayName ?? 'profile'}',
      );
    } catch (e) {
      MyGlobalMessage.show('Switch failed', '$e', MyMessageType.error);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _onBottomNav(int index) {
    final org = context.read<OrgService>();
    if (index == 0) {
      if (!_canManageOwnTeam(org)) {
        MyGlobalMessage.show(
          'Invite',
          'Only the Admin of your own profile can invite members.',
          MyMessageType.info,
        );
        return;
      }
      _showInvitePopup();
    } else if (index == 1) {
      _showJoinPopup();
    }
  }

  Future<void> _showInvitePopup() async {
    final org = context.read<OrgService>();
    final owned = _ownedMembership(org);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InviteOrgDialog(
        orgName: owned?.displayName ?? 'profile',
        orgId: owned?.orgId,
      ),
    );
    if (mounted) await _loadOwnTeam();
  }

  Future<void> _showJoinPopup() async {
    final joined = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _JoinOrgDialog(),
    );
    if (joined == true && mounted) {
      await _loadOwnTeam();
    }
  }

  Widget _orgTile(OrgMembership m, {required bool active}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isMine = uid != null && (m.ownerUid == uid || m.orgId == uid);
    final roleLabel = orgRoleLabel(m.role);
    final subtitle = isMine && m.isAdmin
        ? 'You · Admin'
        : 'Your role · $roleLabel';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: colorAppTitle,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          onTap: _switching ? null : () => _switchOrg(m.orgId),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: active ? colorOrange : Colors.transparent,
              width: 2,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: active ? colorOrange : colorAppBar,
            child: Icon(
              isMine ? Icons.home_outlined : Icons.business_outlined,
              color: Colors.white,
            ),
          ),
          title: Text(
            m.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          trailing: active
              ? const Icon(Icons.check_circle, color: colorOrange)
              : const Icon(Icons.chevron_right, color: Colors.white38),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgService>();
    final memberships = org.memberships;
    final activeId = org.orgId;

    // Own org first, then others by name.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final sorted = [...memberships]..sort((a, b) {
        final aMine = uid != null && (a.ownerUid == uid || a.orgId == uid);
        final bMine = uid != null && (b.ownerUid == uid || b.orgId == uid);
        if (aMine && !bMine) return -1;
        if (!aMine && bMine) return 1;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });

    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_loadingMembers || _switching)
                ? null
                : () => _loadOwnTeam(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colorOrange,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'My Profiles'),
            Tab(text: 'Linked Profiles'),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        onTap: _onBottomNav,
        type: BottomNavigationBarType.fixed,
        backgroundColor: colorAppBar,
        unselectedItemColor: Colors.grey,
        selectedItemColor: Colors.grey,
        items: [
          MyBottomNavItem(
            icon: Icons.person_add_alt_1_outlined,
            label: 'Invite',
            color: _canManageOwnTeam(org) ? Colors.white : Colors.white38,
          ),
          MyBottomNavItem(
            icon: Icons.group_add_outlined,
            label: 'Join',
          ),
        ],
      ),
      body: _switching
          ? myProgressCircle()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMyProfilesTab(sorted, activeId),
                _buildLinkedProfilesTab(org),
              ],
            ),
    );
  }

  Widget _buildMyProfilesTab(List<OrgMembership> sorted, String? activeId) {
    if (sorted.isEmpty) {
      return myCenterMsg('No profiles yet');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: MyText(
            text: 'Tap a profile to switch',
            color: Colors.white70,
            fontsize: 14,
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              ...sorted.map(
                (m) => _orgTile(m, active: m.orgId == activeId),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLinkedProfilesTab(OrgService org) {
    if (_ownedMembership(org) == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: MyText(
          text:
              'Create your own profile to invite and manage linked members.',
          color: Colors.white70,
          fontsize: 14,
        ),
      );
    }
    if (_loadingMembers) {
      return const Center(
        child: CircularProgressIndicator(color: colorProgressCircle),
      );
    }
    if (_members.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: MyText(
          text: 'No linked members yet.',
          color: Colors.white70,
          fontsize: 14,
        ),
      );
    }

    return ListView(
      children: [
        const SizedBox(height: 8),
        ..._members.map((member) {
          final canManage = _canManageOwnTeam(org) &&
              member.role != orgRoleAdmin &&
              member.uid != FirebaseAuth.instance.currentUser?.uid;
          final tile = ListTile(
            tileColor: colorAppTitle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onTap: canManage ? () => _editMemberRole(member) : null,
            title: Text(
              member.displayName.isNotEmpty
                  ? member.displayName
                  : member.email,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              [
                orgRoleLabel(member.role),
                if (member.email.isNotEmpty) member.email,
                if (canManage) 'Tap to change role',
              ].join(' · '),
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: canManage
                ? const Icon(
                    Icons.edit_outlined,
                    color: Colors.white54,
                  )
                : null,
          );

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            child: canManage
                ? Slidable(
                    key: ValueKey('member-${member.uid}'),
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.28,
                      children: [
                        CustomSlidableAction(
                          onPressed: (_) => _confirmRemoveMember(member),
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.delete_outline, size: 28),
                              SizedBox(height: 4),
                              Text('Delete', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    child: tile,
                  )
                : tile,
          );
        }),
        if (_canManageOwnTeam(org))
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: MyText(
              text: 'Tap to change role · swipe left to remove.',
              color: Colors.white54,
              fontsize: 12,
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _confirmRemoveMember(OrgMemberRow member) async {
    final name = member.displayName.isNotEmpty
        ? member.displayName
        : (member.email.isNotEmpty ? member.email : 'this member');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorAppTitle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.blue, width: 2),
        ),
        title: const MyText(
          text: 'Remove member?',
          color: Colors.white,
          fontsize: 20,
        ),
        content: MyText(
          text: 'Remove $name from this profile?',
          color: Colors.white70,
          fontsize: 14,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const MyText(text: 'Cancel', fontsize: 18),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const MyText(
              text: 'Delete',
              color: Colors.redAccent,
              fontsize: 18,
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final org = context.read<OrgService>();
      final owned = _ownedMembership(org);
      await org.removeMember(
        memberUid: member.uid,
        orgId: owned?.orgId ?? _teamOrgId,
      );
      if (!mounted) return;
      await _loadOwnTeam();
      if (!mounted) return;
      MyGlobalSnackBar.show('Member removed');
    } catch (e) {
      MyGlobalMessage.show('Remove failed', '$e', MyMessageType.error);
    }
  }

  Future<void> _editMemberRole(OrgMemberRow member) async {
    final org = context.read<OrgService>();
    if (!_canManageOwnTeam(org)) return;

    var selected = orgInviteRoleList.contains(member.role)
        ? member.role
        : orgRoleEmployee;

    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: colorAppTitle,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Colors.blue, width: 2),
              ),
              title: const MyText(
                text: 'Change role',
                color: Colors.white,
                fontsize: 20,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MyText(
                    text: member.displayName.isNotEmpty
                        ? member.displayName
                        : member.email,
                    color: Colors.white70,
                    fontsize: 14,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey('edit-role-$selected'),
                    dropdownColor: colorAppBar,
                    decoration: const InputDecoration(
                      labelText: 'Access Level',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue, width: 2),
                      ),
                    ),
                    initialValue: selected,
                    items: orgInviteRoleList
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(
                              orgRoleLabel(r),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() => selected = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const MyText(text: 'Cancel', fontsize: 18),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const MyText(
                    text: 'Save',
                    color: Colors.white,
                    fontsize: 18,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == null || !mounted) return;
    if (confirmed == member.role) return;

    try {
      final owned = _ownedMembership(org);
      await org.updateMemberRole(
        memberUid: member.uid,
        role: confirmed,
        orgId: owned?.orgId ?? _teamOrgId,
      );
      if (!mounted) return;
      await _loadOwnTeam();
      if (!mounted) return;
      MyGlobalSnackBar.show('Role updated to ${orgRoleLabel(confirmed)}');
    } catch (e) {
      MyGlobalMessage.show('Update failed', '$e', MyMessageType.error);
    }
  }
}

class _InviteOrgDialog extends StatefulWidget {
  final String orgName;
  final String? orgId;

  const _InviteOrgDialog({required this.orgName, this.orgId});

  @override
  State<_InviteOrgDialog> createState() => _InviteOrgDialogState();
}

class _InviteOrgDialogState extends State<_InviteOrgDialog> {
  String _inviteRole = orgRoleSupervisor;
  String? _lastCode;
  bool _creating = false;

  static const _inviteLabels = {
    orgRoleSupervisor: 'Supervisor',
    orgRoleEmployee: 'Employee',
  };

  Future<void> _createInvite() async {
    setState(() => _creating = true);
    try {
      final code = await context.read<OrgService>().createInvite(
            role: _inviteRole,
            orgId: widget.orgId,
          );
      if (!mounted) return;
      setState(() {
        _lastCode = code;
        _creating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      MyGlobalMessage.show('Invite', '$e', MyMessageType.error);
    }
  }

  Future<void> _shareCode(String code) async {
    final role = orgRoleLabel(_inviteRole);
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Join ${widget.orgName} on Limitless IoT as $role.\n\nJoin code: $code\n\nOpen the app → Link Profile → Join.',
        subject: 'Join ${widget.orgName}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: colorAppTitle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.blue, width: 2),
      ),
      title: const MyText(text: 'Invite', color: Colors.white, fontsize: 20),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyText(
              text: 'Invite someone to ${widget.orgName}',
              color: Colors.white70,
              fontsize: 14,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('invite-role-$_inviteRole'),
              dropdownColor: colorAppBar,
              decoration: const InputDecoration(
                labelText: 'Access Level',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue, width: 2),
                ),
              ),
              initialValue: _inviteRole,
              items: orgInviteRoleList
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(
                        _inviteLabels[r] ?? r,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _inviteRole = v;
                  _lastCode = null;
                });
              },
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorOrange,
                foregroundColor: Colors.white,
              ),
              onPressed: _creating ? null : _createInvite,
              child: _creating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorProgressCircle,
                      ),
                    )
                  : const Text('Generate join code'),
            ),
            if (_lastCode != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                _lastCode!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Valid 7 days · one-time use',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _lastCode!));
                      MyGlobalSnackBar.show('Code copied');
                    },
                    icon: const Icon(Icons.copy, color: Colors.white),
                    label: const Text('Copy', style: TextStyle(color: Colors.white)),
                  ),
                  TextButton.icon(
                    onPressed: () => _shareCode(_lastCode!),
                    icon: const Icon(Icons.share, color: Colors.white),
                    label:
                        const Text('Share', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: colorAppTitle,
                ),
                onPressed: () {
                  final code = _lastCode!;
                  final name = widget.orgName;
                  // Prefer a full-screen route over a nested dialog — QrImageView
                  // inside stacked AlertDialogs can crash on some devices.
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => _OrgInviteQrPage(
                        code: code,
                        orgName: name,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Show QR code'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const MyText(text: 'Close', fontsize: 18),
        ),
      ],
    );
  }
}

class _OrgInviteQrPage extends StatefulWidget {
  final String code;
  final String orgName;

  const _OrgInviteQrPage({
    required this.code,
    required this.orgName,
  });

  @override
  State<_OrgInviteQrPage> createState() => _OrgInviteQrPageState();
}

class _OrgInviteQrPageState extends State<_OrgInviteQrPage> {
  late final Future<Uint8List?> _qrBytes;

  @override
  void initState() {
    super.initState();
    _qrBytes = _buildQrPng(encodeOrgInviteQr(widget.code));
  }

  Future<Uint8List?> _buildQrPng(String data) async {
    try {
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF000000),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF000000),
        ),
      );
      final imageData = await painter.toImageData(560);
      return imageData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle('Join QR code'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.orgName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                FutureBuilder<Uint8List?>(
                  future: _qrBytes,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const SizedBox(
                        width: 280,
                        height: 280,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: colorProgressCircle,
                          ),
                        ),
                      );
                    }
                    final bytes = snap.data;
                    if (bytes == null) {
                      return SizedBox(
                        width: 280,
                        height: 280,
                        child: Center(
                          child: Text(
                            'Could not create QR code.\nUse this code instead:\n${widget.code}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      );
                    }
                    return Container(
                      width: 280,
                      height: 280,
                      color: Colors.white,
                      alignment: Alignment.center,
                      child: Image.memory(
                        bytes,
                        width: 280,
                        height: 280,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  widget.code,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 32,
                    letterSpacing: 4,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Scan this in Link Profile → Join',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(180, 44),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinOrgDialog extends StatefulWidget {
  const _JoinOrgDialog();

  @override
  State<_JoinOrgDialog> createState() => _JoinOrgDialogState();
}

class _JoinOrgDialogState extends State<_JoinOrgDialog> {
  final _codeController = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    if (kIsWeb) {
      MyGlobalMessage.show(
        'Scan QR',
        'Camera scan is available on the mobile app.',
        MyMessageType.info,
      );
      return;
    }
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _OrgInviteScanPage()),
    );
    if (!mounted || code == null || code.isEmpty) return;
    setState(() => _codeController.text = code);
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      MyGlobalMessage.show(
        'Code required',
        'Enter or scan the join code from the Admin.',
        MyMessageType.info,
      );
      return;
    }
    setState(() => _joining = true);
    try {
      final org = context.read<OrgService>();
      await org.acceptInvite(code);
      if (!mounted) return;
      MyGlobalSnackBar.show(
        'Joined ${org.membership?.displayName ?? 'profile'}',
      );
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      MyGlobalMessage.show(
        'Join failed',
        e.message ?? e.code,
        MyMessageType.error,
      );
    } catch (e) {
      MyGlobalMessage.show('Join failed', '$e', MyMessageType.error);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: colorAppTitle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.blue, width: 2),
      ),
      title: const MyText(text: 'Join', color: Colors.white, fontsize: 20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MyText(
            text: 'Enter a join code, or scan the Admin QR code.',
            color: Colors.white70,
            fontsize: 14,
          ),
          const SizedBox(height: 16),
          MyTextFormField(
            controller: _codeController,
            hintText: 'Join code',
            backgroundColor: colorAppBackground,
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            onPressed: _joining ? null : _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _joining ? null : () => Navigator.pop(context, false),
          child: const MyText(text: 'Cancel', fontsize: 18),
        ),
        TextButton(
          onPressed: _joining ? null : _join,
          child: _joining
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorProgressCircle,
                  ),
                )
              : const MyText(
                  text: 'Join',
                  color: Colors.white,
                  fontsize: 18,
                ),
        ),
      ],
    );
  }
}

class _OrgInviteScanPage extends StatefulWidget {
  const _OrgInviteScanPage();

  @override
  State<_OrgInviteScanPage> createState() => _OrgInviteScanPageState();
}

class _OrgInviteScanPageState extends State<_OrgInviteScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final code = decodeOrgInviteQr(raw);
      if (code == null) continue;
      _handled = true;
      Navigator.pop(context, code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle('Scan join code'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Point the camera at the profile QR code',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
