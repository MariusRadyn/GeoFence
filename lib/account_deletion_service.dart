import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geofence/utils.dart';

/// Deletes Firestore/Storage app data for the signed-in user.
class AccountDeletionService {
  AccountDeletionService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Removes app data but keeps the Firebase Auth account and a basic profile.
  static Future<void> deleteCurrentUserDataOnly({
    String? password,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'You are not signed in.',
      );
    }

    await _reauthenticateIfNeeded(
      user,
      password,
      missingPasswordMessage: 'Enter your password to confirm data deletion.',
    );

    await _deleteUserAppData(user.uid);
    await _deleteUserStorage(user.uid);
    await _resetUserProfileDoc(user);
  }

  /// Removes app data, profile document, storage, and the Auth account.
  static Future<void> deleteCurrentUserAccount({
    String? password,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'You are not signed in.',
      );
    }

    await _reauthenticateIfNeeded(
      user,
      password,
      missingPasswordMessage: 'Enter your password to confirm account deletion.',
    );

    final uid = user.uid;
    await _deleteUserAppData(uid);
    await _deleteUserStorage(uid);
    await _db.collection(collectionUsers).doc(uid).delete();
    await user.delete();
  }

  static Future<void> _reauthenticateIfNeeded(
    User user,
    String? password, {
    required String missingPasswordMessage,
  }) async {
    final email = user.email;
    if (email == null || email.isEmpty) return;

    final usesPassword = user.providerData.any(
      (p) => p.providerId == EmailAuthProvider.PROVIDER_ID,
    );
    if (!usesPassword) return;

    if (password == null || password.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-password',
        message: missingPasswordMessage,
      );
    }

    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  static Future<void> _deleteUserAppData(String uid) async {
    final userRef = _db.collection(collectionUsers).doc(uid);

    await _deleteNestedCollection(
      userRef.collection(collectionTrackingSessions),
      [collectionLocations],
    );
    await _deleteNestedCollection(
      userRef.collection(collectionMonitors),
      [collectionIotData],
    );

    await _deleteCollection(userRef.collection(collectionGeoFences));
    await _deleteCollection(userRef.collection(collectionBaseStations));
    await _deleteCollection(userRef.collection(collectionOperators));
    await _deleteCollection(userRef.collection('shop_orders'));
  }

  static Future<void> _resetUserProfileDoc(User user) async {
    final profile = UserData(
      displayName: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email?.split('@').first ?? ''),
      email: user.email,
      emailValidated: user.emailVerified,
    );

    final settings = FireSettings(
      isVoicePromptOn: true,
      logPointPerMeter: 10,
      rebateValuePerLiter: 2.6,
      dieselPrice: 20,
    );

    await _db.collection(collectionUsers).doc(user.uid).set({
      fieldsUserData: profile.toMap(),
      fieldsSettings: settings.toMap(),
    });
  }

  static Future<void> _deleteNestedCollection(
    CollectionReference<Map<String, dynamic>> collection,
    List<String> nestedNames,
  ) async {
    while (true) {
      final snap = await collection.limit(50).get();
      if (snap.docs.isEmpty) break;

      for (final doc in snap.docs) {
        for (final nested in nestedNames) {
          await _deleteCollection(doc.reference.collection(nested));
        }
        await doc.reference.delete();
      }
    }
  }

  static Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snap = await collection.limit(100).get();
      if (snap.docs.isEmpty) break;

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  static Future<void> _deleteUserStorage(String uid) async {
    final paths = [
      'profile_pics/$uid.jpg',
      '$profileTypeUser/$uid',
    ];

    for (final path in paths) {
      await _deleteStoragePath(path);
    }
  }

  static Future<void> _deleteStoragePath(String path) async {
    final ref = FirebaseStorage.instance.ref(path);
    try {
      await ref.delete();
      return;
    } catch (_) {}

    try {
      final listing = await ref.listAll();
      for (final item in listing.items) {
        await item.delete();
      }
      for (final prefix in listing.prefixes) {
        await _deleteStorageFolder(prefix);
      }
    } catch (_) {}
  }

  static Future<void> _deleteStorageFolder(Reference folder) async {
    final listing = await folder.listAll();
    for (final item in listing.items) {
      await item.delete();
    }
    for (final prefix in listing.prefixes) {
      await _deleteStorageFolder(prefix);
    }
  }
}
