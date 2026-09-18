import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// Keep constants local so this file does not import utils.dart (services there
// call [currentDataOwnerUid] and would create a circular import).
const String _collectionUsers = 'users';
const String _collectionOrganizations = 'organizations';
const String _collectionOrgMembers = 'members';
const String _collectionOrgInvites = 'invites';
const String _collectionBaseStations = 'baseStations';
const String _collectionOperators = 'operators';
const String _collectionMonitors = 'monitors';
const String _fieldsSettings = 'settings';
const String _fieldsUserData = 'userdata';
const String _fieldsOrg = 'org';
const String _fieldsOrgs = 'orgs';
const String _fieldsActiveOrgId = 'activeOrgId';
const String _cloudFunctionsRegion = 'europe-west1';

const String orgRoleAdmin = 'admin';
const String orgRoleSupervisor = 'supervisor';
const String orgRoleEmployee = 'employee';

const List<String> orgInviteRoleList = [
  orgRoleSupervisor,
  orgRoleEmployee,
];

String orgRoleLabel(String role) {
  switch (role) {
    case orgRoleAdmin:
      return 'Admin';
    case orgRoleSupervisor:
      return 'Supervisor';
    case orgRoleEmployee:
      return 'Employee';
    default:
      return role;
  }
}

/// Replaces legacy auto-names that used "Farm"/"Organisation" with "Profile".
String normalizeOrganisationName(String? name) {
  var n = (name ?? '').trim();
  if (n.isEmpty) return n;
  if (n.toLowerCase() == 'my farm' || n.toLowerCase() == 'my organisation') {
    return 'My Profile';
  }
  n = n.replaceAll(RegExp(r"'s Farm$", caseSensitive: false), "'s Profile");
  n = n.replaceAll(
    RegExp(r"'s Organisation$", caseSensitive: false),
    "'s Profile",
  );
  n = n.replaceAll(RegExp(r'\bFarms\b', caseSensitive: false), 'Profiles');
  n = n.replaceAll(RegExp(r'\bFarm\b', caseSensitive: false), 'Profile');
  n = n.replaceAll(
    RegExp(r'\bOrganisations\b', caseSensitive: false),
    'Profiles',
  );
  n = n.replaceAll(
    RegExp(r'\bOrganizations\b', caseSensitive: false),
    'Profiles',
  );
  n = n.replaceAll(
    RegExp(r'\bOrganisation\b', caseSensitive: false),
    'Profile',
  );
  n = n.replaceAll(
    RegExp(r'\bOrganization\b', caseSensitive: false),
    'Profile',
  );
  return n;
}

/// Global org context — used by [currentDataOwnerUid] without BuildContext.
final OrgService orgService = OrgService();

/// Organisation data owner uid (Admin). Falls back to signed-in user when no org yet.
String? currentDataOwnerUid() {
  final owner = orgService.dataOwnerUid;
  if (owner != null && owner.isNotEmpty) return owner;
  return FirebaseAuth.instance.currentUser?.uid;
}

class OrgMembership {
  final String orgId;
  final String role;
  final String ownerUid;
  final String? orgName;

  const OrgMembership({
    required this.orgId,
    required this.role,
    required this.ownerUid,
    this.orgName,
  });

  bool get isAdmin => role == orgRoleAdmin;
  bool get isSupervisor => role == orgRoleSupervisor;
  bool get isEmployee => role == orgRoleEmployee;
  bool get canManageMembers => isAdmin;
  bool get canEditFarm => isAdmin || isSupervisor;
  bool get canManageBilling => isAdmin;

  String get displayName {
    final name = normalizeOrganisationName(orgName);
    if (name.isNotEmpty) return name;
    return 'Profile';
  }

  factory OrgMembership.fromMap(Map<String, dynamic> map, {String? orgId}) {
    return OrgMembership(
      orgId: (orgId ?? map['orgId'] ?? '').toString(),
      role: (map['role'] ?? orgRoleEmployee).toString(),
      ownerUid: (map['ownerUid'] ?? orgId ?? map['orgId'] ?? '').toString(),
      orgName: normalizeOrganisationName(map['orgName']?.toString()),
    );
  }

  Map<String, dynamic> toMap() => {
        'orgId': orgId,
        'role': role,
        'ownerUid': ownerUid,
        if (orgName != null && orgName!.isNotEmpty) 'orgName': orgName,
      };

  /// Stored under users/{uid}.orgs.{orgId} (orgId is the map key).
  Map<String, dynamic> toOrgsEntry() => {
        'role': role,
        'ownerUid': ownerUid,
        if (orgName != null && orgName!.isNotEmpty) 'orgName': orgName,
      };
}

class OrgMemberRow {
  final String uid;
  final String role;
  final String displayName;
  final String email;
  final DateTime? joinedAt;

  const OrgMemberRow({
    required this.uid,
    required this.role,
    required this.displayName,
    required this.email,
    this.joinedAt,
  });

  factory OrgMemberRow.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    DateTime? joined;
    final raw = data['joinedAt'];
    if (raw is Timestamp) joined = raw.toDate();
    return OrgMemberRow(
      uid: doc.id,
      role: (data['role'] ?? orgRoleEmployee).toString(),
      displayName: (data['displayName'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      joinedAt: joined,
    );
  }
}

class OrgService extends ChangeNotifier {
  final List<OrgMembership> _memberships = [];
  OrgMembership? _membership;
  bool isLoading = false;
  bool isReady = false;
  bool needsSetup = false;
  String? errorMsg;
  Future<void>? _loadInFlight;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  String? _userDocListenUid;
  bool _liveSyncReady = false;
  int _suppressRemovalNotices = 0;
  final List<Future<void> Function()> _farmReloaders = [];
  final List<void Function(String oldRole, String newRole, String orgName)>
      _roleChangeHandlers = [];
  final List<void Function(String removedOrgName, String? switchedToOrgName)>
      _membershipRemovedHandlers = [];

  List<OrgMembership> get memberships => List.unmodifiable(_memberships);
  OrgMembership? get membership => _membership;
  String? get dataOwnerUid => _membership?.ownerUid;
  String? get orgId => _membership?.orgId;
  String? get role => _membership?.role;
  bool get hasOrg => _membership != null;
  bool get isAdmin => _membership?.isAdmin == true;
  bool get canManageMembers => _membership?.canManageMembers == true;
  bool get canEditFarm => _membership?.canEditFarm == true;
  bool get canManageBilling => _membership?.canManageBilling == true;
  bool get canJoinMoreOrganisations => hasOrg;

  /// True when user already owns an organisation (orgId == their uid).
  bool get ownsAnOrganisation {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    return _memberships.any((m) => m.ownerUid == uid || m.orgId == uid);
  }

  OrgService() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _stopUserDocListener();
        _memberships.clear();
        _membership = null;
        needsSetup = false;
        isReady = true;
        isLoading = false;
        errorMsg = null;
        notifyListeners();
      } else {
        load();
      }
    });
  }

  void registerFarmReloader(Future<void> Function() reloader) {
    _farmReloaders.add(reloader);
  }

  void registerRoleChangeHandler(
    void Function(String oldRole, String newRole, String orgName) handler,
  ) {
    _roleChangeHandlers.add(handler);
  }

  void unregisterRoleChangeHandler(
    void Function(String oldRole, String newRole, String orgName) handler,
  ) {
    _roleChangeHandlers.remove(handler);
  }

  void registerMembershipRemovedHandler(
    void Function(String removedOrgName, String? switchedToOrgName) handler,
  ) {
    _membershipRemovedHandlers.add(handler);
  }

  void unregisterMembershipRemovedHandler(
    void Function(String removedOrgName, String? switchedToOrgName) handler,
  ) {
    _membershipRemovedHandlers.remove(handler);
  }

  void _notifyRoleChanged(String oldRole, String newRole, String orgName) {
    for (final handler in List.of(_roleChangeHandlers)) {
      try {
        handler(oldRole, newRole, orgName);
      } catch (e) {
        debugPrint('Org role-change handler error: $e');
      }
    }
  }

  void _notifyMembershipRemoved(
    String removedOrgName,
    String? switchedToOrgName,
  ) {
    for (final handler in List.of(_membershipRemovedHandlers)) {
      try {
        handler(removedOrgName, switchedToOrgName);
      } catch (e) {
        debugPrint('Org membership-removed handler error: $e');
      }
    }
  }

  /// Ignore remote "removed from profile" popups while we apply local joins/switches.
  Future<T> _withRemovalNoticesSuppressed<T>(Future<T> Function() action) async {
    _suppressRemovalNotices++;
    try {
      return await action();
    } finally {
      // Allow in-flight Firestore snapshots from this mutation to settle.
      Future<void>.delayed(const Duration(milliseconds: 2500), () {
        if (_suppressRemovalNotices > 0) _suppressRemovalNotices--;
      });
    }
  }

  void _stopUserDocListener() {
    _liveSyncReady = false;
    _userDocSub?.cancel();
    _userDocSub = null;
    _userDocListenUid = null;
  }

  void _ensureUserDocListener(String uid) {
    if (_userDocListenUid == uid && _userDocSub != null) return;
    _userDocSub?.cancel();
    _userDocListenUid = uid;
    _userDocSub = FirebaseFirestore.instance
        .collection(_collectionUsers)
        .doc(uid)
        .snapshots()
        .listen(
      _onUserDocSnapshot,
      onError: (e) => debugPrint('Org user-doc listen error: $e'),
    );
  }

  void _onUserDocSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!_liveSyncReady) return;
    if (!snap.exists) return;
    final data = snap.data();
    if (data == null) return;
    unawaited(_applyRemoteUserDoc(data));
  }

  Future<void> _applyRemoteUserDoc(Map<String, dynamic> data) async {
    if (!_liveSyncReady) return;

    var list = _parseOrgsMap(data[_fieldsOrgs]);
    // Preserve display names already resolved locally (snapshot may omit orgName).
    list = list.map((m) {
      if ((m.orgName ?? '').trim().isNotEmpty) return m;
      for (final existing in _memberships) {
        if (existing.orgId == m.orgId &&
            (existing.orgName ?? '').trim().isNotEmpty) {
          return OrgMembership(
            orgId: m.orgId,
            role: m.role,
            ownerUid: m.ownerUid,
            orgName: existing.orgName,
          );
        }
      }
      return m;
    }).toList();
    list.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    final activeId = data[_fieldsActiveOrgId]?.toString();
    final prevActive = _membership;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    OrgMembership? findOwned(List<OrgMembership> source) {
      if (uid == null) return null;
      for (final m in source) {
        if (m.orgId == uid || m.ownerUid == uid) return m;
      }
      return null;
    }

    OrgMembership? active;
    if (activeId != null && activeId.isNotEmpty) {
      for (final m in list) {
        if (m.orgId == activeId) {
          active = m;
          break;
        }
      }
    }
    active ??= list.isNotEmpty ? list.first : null;

    // Prefer mirrored org.role when it matches the active org (single-field write).
    final orgMirror = data[_fieldsOrg];
    if (active != null && orgMirror is Map) {
      final mirrorId = orgMirror['orgId']?.toString();
      final mirrorRole = orgMirror['role']?.toString();
      if (mirrorId == active.orgId &&
          mirrorRole != null &&
          mirrorRole.isNotEmpty &&
          mirrorRole != active.role) {
        final patched = OrgMembership(
          orgId: active.orgId,
          role: mirrorRole,
          ownerUid: active.ownerUid,
          orgName: active.orgName,
        );
        active = patched;
        list = [
          for (final m in list)
            if (m.orgId == patched.orgId) patched else m,
        ];
      }
    }

    final removedFromActive = prevActive != null &&
        !list.any((m) => m.orgId == prevActive.orgId);
    // Only treat as a remote kick when a *linked* profile disappeared — never
    // for own Admin profile sync glitches, and never during local join/switch.
    final wasLinkedProfile = uid != null &&
        prevActive != null &&
        prevActive.orgId != uid &&
        prevActive.ownerUid != uid;
    final shouldAnnounceRemoval = removedFromActive &&
        wasLinkedProfile &&
        _suppressRemovalNotices == 0;
    final removedOrgName =
        shouldAnnounceRemoval ? prevActive.displayName : null;

    // If the active linked profile was removed, fall back to owned Admin profile.
    var switchedToOwned = false;
    if (removedFromActive && wasLinkedProfile) {
      final owned = findOwned(list);
      if (owned != null && active?.orgId != owned.orgId) {
        active = owned;
        switchedToOwned = true;
      }
    }

    final roleChanged = prevActive != null &&
        active != null &&
        prevActive.orgId == active.orgId &&
        prevActive.role != active.role;

    final oldRole = prevActive?.role;
    final newRole = active?.role;
    final orgName = active?.displayName ?? 'profile';

    final membershipChanged = prevActive?.orgId != active?.orgId ||
        prevActive?.role != active?.role ||
        _memberships.length != list.length;

    _memberships
      ..clear()
      ..addAll(list);
    _membership = active;
    needsSetup = list.isEmpty;
    isReady = true;
    isLoading = false;

    if (switchedToOwned && active != null && uid != null) {
      try {
        await FirebaseFirestore.instance.collection(_collectionUsers).doc(uid).set({
          _fieldsActiveOrgId: active.orgId,
          _fieldsOrg: active.toMap(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Org fall back to owned profile error: $e');
      }
    }

    if (!membershipChanged && !roleChanged && !removedFromActive) return;

    notifyListeners();

    if (shouldAnnounceRemoval && removedOrgName != null) {
      await _reloadFarmData();
      _notifyMembershipRemoved(removedOrgName, active?.displayName);
    } else if (roleChanged && oldRole != null && newRole != null) {
      await _reloadFarmData();
      _notifyRoleChanged(oldRole, newRole, orgName);
    } else if (prevActive?.orgId != active?.orgId) {
      await _reloadFarmData();
    }
  }

  Future<void> ensureLoaded() {
    if (isReady && _loadInFlight == null) return Future.value();
    return _loadInFlight ?? load();
  }

  Future<void> _reloadFarmData() async {
    for (final fn in List<Future<void> Function()>.from(_farmReloaders)) {
      try {
        await fn();
      } catch (e) {
        debugPrint('Org data reload error: $e');
      }
    }
  }

  Future<void> load() async {
    if (_loadInFlight != null) return _loadInFlight!;
    _loadInFlight = _loadInternal();
    try {
      await _loadInFlight;
    } finally {
      _loadInFlight = null;
    }
  }

  List<OrgMembership> _parseOrgsMap(dynamic raw) {
    if (raw is! Map) return [];
    final list = <OrgMembership>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      final id = key.toString();
      if (id.isEmpty) return;
      list.add(OrgMembership.fromMap(
        Map<String, dynamic>.from(value),
        orgId: id,
      ));
    });
    list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return list;
  }

  Future<OrgMembership> _withOrgName(OrgMembership m) async {
    String? fromMember = normalizeOrganisationName(m.orgName);
    String? fromOrgDoc;
    if (m.orgId.isNotEmpty) {
      final orgDoc = await FirebaseFirestore.instance
          .collection(_collectionOrganizations)
          .doc(m.orgId)
          .get();
      fromOrgDoc = orgDoc.data()?['name']?.toString();
    }
    final rawOrgDoc = (fromOrgDoc ?? '').trim();
    final normalizedDoc = normalizeOrganisationName(fromOrgDoc);
    final name = fromMember.isNotEmpty
        ? fromMember
        : (normalizedDoc.isNotEmpty ? normalizedDoc : '');

    final updated = OrgMembership(
      orgId: m.orgId,
      role: m.role,
      ownerUid: m.ownerUid,
      orgName: name.isNotEmpty ? name : null,
    );

    final memberNeedsFix = (m.orgName ?? '').trim().isNotEmpty &&
        normalizeOrganisationName(m.orgName) != (m.orgName ?? '').trim();
    final docNeedsFix =
        rawOrgDoc.isNotEmpty && normalizeOrganisationName(rawOrgDoc) != rawOrgDoc;

    if (name.isNotEmpty && (memberNeedsFix || docNeedsFix)) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final batch = FirebaseFirestore.instance.batch();
        batch.set(
          FirebaseFirestore.instance
              .collection(_collectionOrganizations)
              .doc(m.orgId),
          {'name': name},
          SetOptions(merge: true),
        );
        if (uid != null) {
          final patch = <String, dynamic>{
            '$_fieldsOrgs.${m.orgId}': updated.toOrgsEntry(),
          };
          batch.set(
            FirebaseFirestore.instance.collection(_collectionUsers).doc(uid),
            patch,
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      } catch (e) {
        debugPrint('Org name normalize persist error: $e');
      }
    }

    return updated;
  }

  Future<void> _loadInternal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _stopUserDocListener();
      _memberships.clear();
      _membership = null;
      needsSetup = false;
      isReady = true;
      isLoading = false;
      notifyListeners();
      return;
    }

    _liveSyncReady = false;
    isLoading = true;
    errorMsg = null;
    notifyListeners();

    try {
      final uid = user.uid;
      final userRef =
          FirebaseFirestore.instance.collection(_collectionUsers).doc(uid);
      final userDoc = await userRef.get();
      final data = userDoc.data();

      var list = _parseOrgsMap(data?[_fieldsOrgs]);
      final legacy = data?[_fieldsOrg];
      final activeId = data?[_fieldsActiveOrgId]?.toString();

      // Migrate legacy single `org` into `orgs` + `activeOrgId`.
      if (list.isEmpty && legacy is Map) {
        final m = OrgMembership.fromMap(Map<String, dynamic>.from(legacy));
        if (m.orgId.isNotEmpty) {
          list = [await _withOrgName(m)];
          await userRef.set({
            _fieldsOrgs: {m.orgId: list.first.toOrgsEntry()},
            _fieldsActiveOrgId: m.orgId,
            _fieldsOrg: list.first.toMap(),
          }, SetOptions(merge: true));
        }
      }

      // Always keep the user's own Admin organisation in the list when it exists.
      list = await _ensureOwnedOrganisationInList(uid, list);

      if (list.isNotEmpty) {
        final enriched = <OrgMembership>[];
        for (final m in list) {
          enriched.add(await _withOrgName(m));
        }
        _memberships
          ..clear()
          ..addAll(enriched);

        // Persist full orgs map so a prior join cannot drop the owned org.
        final orgsMap = <String, dynamic>{
          for (final m in _memberships) m.orgId: m.toOrgsEntry(),
        };
        await userRef.set({_fieldsOrgs: orgsMap}, SetOptions(merge: true));

        OrgMembership? active;
        if (activeId != null && activeId.isNotEmpty) {
          for (final m in _memberships) {
            if (m.orgId == activeId) {
              active = m;
              break;
            }
          }
        }
        active ??= _memberships.first;
        _membership = active;
        needsSetup = false;

        // Keep activeOrgId / org mirror in sync.
        if (activeId != active.orgId || legacy is! Map) {
          await userRef.set({
            _fieldsActiveOrgId: active.orgId,
            _fieldsOrg: active.toMap(),
          }, SetOptions(merge: true));
        }
      } else if (userDoc.exists && await _hasFarmData(uid)) {
        await _migrateExistingUserToAdmin(uid, data);
      } else if (userDoc.exists) {
        _memberships.clear();
        _membership = null;
        needsSetup = true;
      } else {
        _memberships.clear();
        _membership = null;
        needsSetup = false;
      }

      isReady = true;
      isLoading = false;
      _liveSyncReady = true;
      _ensureUserDocListener(uid);
      notifyListeners();
      if (hasOrg) {
        await _reloadFarmData();
      }
    } catch (e) {
      errorMsg = '$e';
      isReady = true;
      isLoading = false;
      _liveSyncReady = true;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) _ensureUserDocListener(uid);
      debugPrint('OrgService.load error: $e');
      notifyListeners();
    }
  }

  Future<void> refreshAfterProfileReady() async {
    needsSetup = false;
    isReady = false;
    await load();
  }

  Future<bool> _hasFarmData(String uid) async {
    final userRef =
        FirebaseFirestore.instance.collection(_collectionUsers).doc(uid);
    final doc = await userRef.get();
    if (doc.data()?[_fieldsSettings] != null) return true;

    Future<bool> hasDocs(String collection) async {
      final snap = await userRef.collection(collection).limit(1).get();
      return snap.docs.isNotEmpty;
    }

    if (await hasDocs(_collectionBaseStations)) return true;
    if (await hasDocs(_collectionOperators)) return true;
    if (await hasDocs(_collectionMonitors)) return true;
    return false;
  }

  /// If this user owns an organisation (orgId == uid), make sure it stays in
  /// their membership list — joining another org must never remove it.
  Future<List<OrgMembership>> _ensureOwnedOrganisationInList(
    String uid,
    List<OrgMembership> list,
  ) async {
    if (list.any((m) => m.orgId == uid || m.ownerUid == uid)) {
      return list;
    }

    final orgRef =
        FirebaseFirestore.instance.collection(_collectionOrganizations).doc(uid);
    final orgDoc = await orgRef.get();
    final ownerOnDoc = orgDoc.data()?['ownerUid']?.toString();
    final hasOwnedOrgDoc = orgDoc.exists &&
        (ownerOnDoc == null || ownerOnDoc.isEmpty || ownerOnDoc == uid);
    final hasData = await _hasFarmData(uid);

    if (!hasOwnedOrgDoc && !hasData) {
      return list;
    }

    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? '';
    final email = user?.email ?? '';
    var orgName = normalizeOrganisationName(orgDoc.data()?['name']?.toString());
    if (orgName.isEmpty) {
      orgName = displayName.trim().isNotEmpty
          ? "$displayName's Profile"
          : 'My Profile';
    }

    final batch = FirebaseFirestore.instance.batch();
    if (!orgDoc.exists) {
      batch.set(orgRef, {
        'name': orgName,
        'ownerUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'restored': true,
      });
    } else {
      batch.set(
        orgRef,
        {
          'name': orgName,
          'ownerUid': uid,
        },
        SetOptions(merge: true),
      );
    }
    batch.set(
      orgRef.collection(_collectionOrgMembers).doc(uid),
      {
        'role': orgRoleAdmin,
        'displayName': displayName,
        'email': email,
        'joinedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();

    final owned = OrgMembership(
      orgId: uid,
      role: orgRoleAdmin,
      ownerUid: uid,
      orgName: orgName,
    );
    return [...list, owned];
  }

  Future<void> _applyMemberships(
    List<OrgMembership> list, {
    required String activeOrgId,
  }) async {
    await _withRemovalNoticesSuppressed(() async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      OrgMembership? active;
      for (final m in list) {
        if (m.orgId == activeOrgId) {
          active = m;
          break;
        }
      }
      active ??= list.isNotEmpty ? list.first : null;

      _memberships
        ..clear()
        ..addAll(list);
      _membership = active;
      needsSetup = active == null;

      if (active != null) {
        final orgsMap = <String, dynamic>{};
        for (final m in list) {
          orgsMap[m.orgId] = m.toOrgsEntry();
        }
        await FirebaseFirestore.instance.collection(_collectionUsers).doc(uid).set({
          _fieldsOrgs: orgsMap,
          _fieldsActiveOrgId: active.orgId,
          _fieldsOrg: active.toMap(),
        }, SetOptions(merge: true));
      }

      notifyListeners();
      if (active != null) {
        await _reloadFarmData();
      }
    });
  }

  Future<void> _migrateExistingUserToAdmin(
    String uid,
    Map<String, dynamic>? userData,
  ) async {
    final displayName =
        (userData?[_fieldsUserData] is Map
                ? (userData![_fieldsUserData] as Map)['displayName']
                : null)
            ?.toString() ??
        FirebaseAuth.instance.currentUser?.displayName ??
        '';
    final email = FirebaseAuth.instance.currentUser?.email ??
        (userData?[_fieldsUserData] is Map
                ? (userData![_fieldsUserData] as Map)['email']
                : null)
            ?.toString() ??
        '';
    final orgName = displayName.trim().isNotEmpty
        ? "$displayName's Profile"
        : 'My Profile';

    final batch = FirebaseFirestore.instance.batch();
    final orgRef =
        FirebaseFirestore.instance.collection(_collectionOrganizations).doc(uid);
    batch.set(orgRef, {
      'name': orgName,
      'ownerUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'migrated': true,
    });
    batch.set(orgRef.collection(_collectionOrgMembers).doc(uid), {
      'role': orgRoleAdmin,
      'displayName': displayName,
      'email': email,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    final membership = OrgMembership(
      orgId: uid,
      role: orgRoleAdmin,
      ownerUid: uid,
      orgName: orgName,
    );
    batch.set(
      FirebaseFirestore.instance.collection(_collectionUsers).doc(uid),
      {
        _fieldsOrgs: {uid: membership.toOrgsEntry()},
        _fieldsActiveOrgId: uid,
        _fieldsOrg: membership.toMap(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    _memberships
      ..clear()
      ..add(membership);
    _membership = membership;
    needsSetup = false;
  }

  Future<void> createOrganization(String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Profile name required');
    if (ownsAnOrganisation) {
      throw StateError('You already own a profile');
    }

    final uid = user.uid;
    final displayName = user.displayName ?? '';
    final email = user.email ?? '';

    final batch = FirebaseFirestore.instance.batch();
    final orgRef =
        FirebaseFirestore.instance.collection(_collectionOrganizations).doc(uid);
    batch.set(orgRef, {
      'name': trimmed,
      'ownerUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(orgRef.collection(_collectionOrgMembers).doc(uid), {
      'role': orgRoleAdmin,
      'displayName': displayName,
      'email': email,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    final membership = OrgMembership(
      orgId: uid,
      role: orgRoleAdmin,
      ownerUid: uid,
      orgName: trimmed,
    );

    final orgsMap = <String, dynamic>{
      for (final m in _memberships) m.orgId: m.toOrgsEntry(),
      uid: membership.toOrgsEntry(),
    };
    batch.set(
      FirebaseFirestore.instance.collection(_collectionUsers).doc(uid),
      {
        _fieldsOrgs: orgsMap,
        _fieldsActiveOrgId: uid,
        _fieldsOrg: membership.toMap(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();

    final next = [..._memberships.where((m) => m.orgId != uid), membership];
    await _applyMemberships(next, activeOrgId: uid);
    isReady = true;
  }

  Future<void> switchOrganisation(String orgId) async {
    await _withRemovalNoticesSuppressed(() async {
      if (orgId.isEmpty) return;
      if (_membership?.orgId == orgId) return;
      OrgMembership? next;
      for (final m in _memberships) {
        if (m.orgId == orgId) {
          next = m;
          break;
        }
      }
      if (next == null) throw StateError('Profile not found');

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Not signed in');

      await FirebaseFirestore.instance.collection(_collectionUsers).doc(uid).set({
        _fieldsActiveOrgId: next.orgId,
        _fieldsOrg: next.toMap(),
      }, SetOptions(merge: true));

      _membership = next;
      notifyListeners();
      await _reloadFarmData();
    });
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<String> createInvite({required String role, String? orgId}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');

    OrgMembership? org;
    final requestedId = (orgId ?? '').trim();
    if (requestedId.isNotEmpty) {
      for (final m in _memberships) {
        if (m.orgId == requestedId) {
          org = m;
          break;
        }
      }
    } else {
      org = _membership;
    }
    if (org == null) throw StateError('No profile');
    if (!org.isAdmin) throw StateError('Only Admin can invite');
    // Invites are only for a profile you own.
    if (org.orgId != user.uid && org.ownerUid != user.uid) {
      throw StateError('You can only invite members to your own profile');
    }
    if (!orgInviteRoleList.contains(role)) {
      throw ArgumentError('Invalid invite role');
    }

    final code = _generateInviteCode();
    final invites = FirebaseFirestore.instance
        .collection(_collectionOrganizations)
        .doc(org.orgId)
        .collection(_collectionOrgInvites);

    final inviteRef = invites.doc();
    final expiresAt = Timestamp.fromDate(
      DateTime.now().toUtc().add(const Duration(days: 7)),
    );
    final payload = {
      'code': code,
      'codeUpper': code.toUpperCase(),
      'role': role,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      'usedBy': null,
      'usedAt': null,
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.set(inviteRef, payload);
    batch.set(
      FirebaseFirestore.instance
          .collection('orgInviteCodes')
          .doc(code.toUpperCase()),
      {
        'orgId': org.orgId,
        'inviteId': inviteRef.id,
        'role': role,
        'expiresAt': expiresAt,
        'usedBy': null,
      },
    );
    await batch.commit();
    return code;
  }

  Future<void> acceptInvite(String code) async {
    await _withRemovalNoticesSuppressed(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Not signed in');
      final trimmed = code.trim().toUpperCase();
      if (trimmed.length < 4) throw ArgumentError('Invalid code');

      final functions =
          FirebaseFunctions.instanceFor(region: _cloudFunctionsRegion);
      final callable = functions.httpsCallable('acceptOrgInvite');
      final result = await callable.call(<String, dynamic>{'code': trimmed});
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});

      final joined = OrgMembership(
        orgId: (data['orgId'] ?? '').toString(),
        role: (data['role'] ?? orgRoleEmployee).toString(),
        ownerUid: (data['ownerUid'] ?? data['orgId'] ?? '').toString(),
        orgName: data['orgName']?.toString(),
      );

      // Preserve every existing membership (especially the user's own Admin org).
      var next = [
        ..._memberships.where((m) => m.orgId != joined.orgId),
        joined,
      ];
      next = await _ensureOwnedOrganisationInList(user.uid, next);
      await _applyMemberships(next, activeOrgId: joined.orgId);
      isReady = true;
    });
  }

  Future<List<OrgMemberRow>> listMembers({String? orgId}) async {
    final id = (orgId ?? _membership?.orgId ?? '').trim();
    if (id.isEmpty) return [];
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrganizations)
        .doc(id)
        .collection(_collectionOrgMembers)
        .get();
    final list = snap.docs.map(OrgMemberRow.fromDoc).toList();
    list.sort((a, b) {
      if (a.role == orgRoleAdmin && b.role != orgRoleAdmin) return -1;
      if (b.role == orgRoleAdmin && a.role != orgRoleAdmin) return 1;
      return a.displayName
          .toLowerCase()
          .compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  bool _isAdminOfOrg(String orgId) {
    for (final m in _memberships) {
      if (m.orgId == orgId) return m.isAdmin;
    }
    return false;
  }

  bool _ownsOrg(String orgId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    return orgId == uid ||
        _memberships.any((m) => m.orgId == orgId && m.ownerUid == uid);
  }

  /// Admin of the active (or given) organisation can set Supervisor / Employee.
  Future<void> updateMemberRole({
    required String memberUid,
    required String role,
    String? orgId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');

    final id = (orgId ?? _membership?.orgId ?? '').trim();
    if (id.isEmpty) throw StateError('No profile');
    if (!_ownsOrg(id) || !_isAdminOfOrg(id)) {
      throw StateError('Only Admin can change roles');
    }
    if (!orgInviteRoleList.contains(role)) {
      throw ArgumentError('Role must be Supervisor or Employee');
    }
    if (memberUid == user.uid) {
      throw StateError('You cannot change your own role here');
    }
    if (memberUid == id) {
      throw StateError('Cannot change the profile owner role');
    }

    final memberRef = FirebaseFirestore.instance
        .collection(_collectionOrganizations)
        .doc(id)
        .collection(_collectionOrgMembers)
        .doc(memberUid);
    final memberSnap = await memberRef.get();
    if (!memberSnap.exists) throw StateError('Member not found');
    final currentRole = (memberSnap.data()?['role'] ?? '').toString();
    if (currentRole == orgRoleAdmin) {
      throw StateError('Cannot change an Admin role');
    }

    final memberUserRef =
        FirebaseFirestore.instance.collection(_collectionUsers).doc(memberUid);
    final memberUser = await memberUserRef.get();
    final activeId = memberUser.data()?[_fieldsActiveOrgId]?.toString();
    final orgMirror = memberUser.data()?[_fieldsOrg];
    final isActiveOrg = activeId == id ||
        (orgMirror is Map && orgMirror['orgId']?.toString() == id);

    OrgMembership? ownedMeta;
    for (final m in _memberships) {
      if (m.orgId == id) {
        ownedMeta = m;
        break;
      }
    }

    final batch = FirebaseFirestore.instance.batch();
    batch.set(memberRef, {'role': role}, SetOptions(merge: true));

    final userPatch = <String, dynamic>{
      '$_fieldsOrgs.$id.role': role,
    };
    if (isActiveOrg) {
      final updatedOrg = <String, dynamic>{
        if (orgMirror is Map) ...Map<String, dynamic>.from(orgMirror),
        'orgId': id,
        'role': role,
        'ownerUid': ownedMeta?.ownerUid ?? id,
        if (ownedMeta?.orgName != null) 'orgName': ownedMeta!.orgName,
      };
      userPatch[_fieldsOrg] = updatedOrg;
    }

    batch.set(memberUserRef, userPatch, SetOptions(merge: true));
    await batch.commit();
  }

  /// Admin removes a non-owner member from the organisation.
  Future<void> removeMember({
    required String memberUid,
    String? orgId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');

    final id = (orgId ?? _membership?.orgId ?? '').trim();
    if (id.isEmpty) throw StateError('No profile');
    if (!_ownsOrg(id) || !_isAdminOfOrg(id)) {
      throw StateError('Only Admin can remove members');
    }
    if (memberUid == user.uid) {
      throw StateError('You cannot remove yourself here');
    }
    if (memberUid == id) {
      throw StateError('Cannot remove the profile owner');
    }

    final memberRef = FirebaseFirestore.instance
        .collection(_collectionOrganizations)
        .doc(id)
        .collection(_collectionOrgMembers)
        .doc(memberUid);
    final memberSnap = await memberRef.get();
    if (!memberSnap.exists) throw StateError('Member not found');
    if ((memberSnap.data()?['role'] ?? '').toString() == orgRoleAdmin) {
      throw StateError('Cannot remove an Admin');
    }

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(memberRef);

    final memberUserRef =
        FirebaseFirestore.instance.collection(_collectionUsers).doc(memberUid);
    // Remove this org from their memberships map.
    batch.update(memberUserRef, {
      '$_fieldsOrgs.$id': FieldValue.delete(),
    });

    await batch.commit();

    // If that org was active for them, pick another or clear.
    try {
      final memberUser = await memberUserRef.get();
      final data = memberUser.data() ?? {};
      final activeId = data[_fieldsActiveOrgId]?.toString();
      final orgsRaw = data[_fieldsOrgs];
      final remaining = <String, dynamic>{};
      if (orgsRaw is Map) {
        orgsRaw.forEach((k, v) {
          if (k.toString() != id) remaining[k.toString()] = v;
        });
      }

      if (activeId == id || remaining.isEmpty) {
        if (remaining.isEmpty) {
          await memberUserRef.set({
            _fieldsActiveOrgId: FieldValue.delete(),
            _fieldsOrg: FieldValue.delete(),
            _fieldsOrgs: {},
          }, SetOptions(merge: true));
        } else {
          // Prefer their own Admin profile when leaving a linked one.
          String? nextId;
          if (remaining.containsKey(memberUid)) {
            nextId = memberUid;
          } else {
            for (final entry in remaining.entries) {
              final map = entry.value is Map
                  ? Map<String, dynamic>.from(entry.value as Map)
                  : <String, dynamic>{};
              if (map['ownerUid']?.toString() == memberUid) {
                nextId = entry.key;
                break;
              }
            }
          }
          nextId ??= remaining.keys.first;
          final entry = remaining[nextId];
          final map = entry is Map
              ? Map<String, dynamic>.from(entry)
              : <String, dynamic>{};
          await memberUserRef.set({
            _fieldsOrgs: remaining,
            _fieldsActiveOrgId: nextId,
            _fieldsOrg: {
              'orgId': nextId,
              'role': map['role'] ?? orgRoleEmployee,
              'ownerUid': map['ownerUid'] ?? nextId,
              if (map['orgName'] != null) 'orgName': map['orgName'],
            },
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('removeMember mirror sync: $e');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
