import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:image_picker/image_picker.dart';
import 'package:geofence/utils.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

FirebaseStorage fireStorageInstance = FirebaseStorage.instance;
List<Reference> fireAllSongsRef = [];

// ----------------------------------------------------------------------------
// Firebase Storage
// ----------------------------------------------------------------------------
Future<void> fireStoreUploadImage(String inputSource) async {
  final picker = ImagePicker();
  XFile? pickedImage;
  try {
    pickedImage = await picker.pickImage(
      source:
          inputSource == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1920,
    );

    final String fileName = path.basename(pickedImage!.path);
    File imageFile = File(pickedImage.path);

    // Points to the root reference
    final storageRef = FirebaseStorage.instance.ref();
    var spaceRef = storageRef.child("user1/recycle/$fileName");
    await spaceRef.putFile(
      imageFile,
      SettableMetadata(
        customMetadata: {
          'uploaded_by': 'A bad guy',
          'description': 'Some description...',
        },
      ),
    );
  } catch (err) {
    print(err);
  }
}
Future<void> fireStoreUploadFile(String filename) async {
  //Future<String> url = "" as Future<String>;
  try {
    //Create a reference to the location you want to upload to in firebase
    Reference reference = fireStorageInstance.ref().child(fireUserRecyclebin);

    //Upload the file to firebase
    UploadTask uploadTask = reference.putFile(File(filename));

    // Waits till the file is uploaded then stores the download url
    uploadTask.whenComplete(() {
      Future<String> url = reference.getDownloadURL();
    }).catchError((onError) {
      print(onError);
    });
  } catch (err) {
    print(err);
  }
}
Future<List<Map<String, dynamic>>> fireStoreLoadFiles() async {
  List<Map<String, dynamic>> files = [];

  final ListResult result = await fireStorageInstance.ref().list();
  final List<Reference> allFiles = result.items;

  await Future.forEach<Reference>(allFiles, (file) async {
    final String fileUrl = await file.getDownloadURL();
    final FullMetadata fileMeta = await file.getMetadata();
    files.add({
      "url": fileUrl,
      "path": file.fullPath,
      "uploaded_by": fileMeta.customMetadata?['uploaded_by'] ?? 'Nobody',
      "description":
          fileMeta.customMetadata?['description'] ?? 'No description',
    });
  });

  return files;
}
Future<List<Reference>> fireStoreGetFilesList(String path) async {
  try {
    final storageRef = fireStorageInstance.ref().child(path);
    final listResult = await storageRef.listAll();
    fireAllSongsRef.clear();

    for (var item in listResult.items) {
      fireAllSongsRef.add(item);
    }

    return fireAllSongsRef;
  } catch (e) {
    print("fireStoreGetFilesList Error: $e");
    return [];
  }
}
Future<String> fireStoreReadFile(int index) async {
  final storageRef = fireStorageInstance.ref().child(
        fireAllSongsRef[index].fullPath,
      );
  Uint8List? downloadedData = await storageRef.getData();
  String text = utf8.decode(downloadedData as List<int>);
  return text;
}
Future<void> fireStoreWriteFile(String text, int index) async {
  final storageRef = fireStorageInstance.ref().child(
        fireAllSongsRef[index].fullPath,
      );
  storageRef.putString(
    text,
    metadata: SettableMetadata(contentLanguage: 'en'),
  );
}
Future<List<Reference>> fireStoreGetDirectoryList(String path) async {
  final storageRef = fireStorageInstance.ref().child(path);
  final listResult = await storageRef.listAll();
  List<Reference> dir = [];

  for (var prefix in listResult.prefixes) {
    dir.add(prefix);
  }
  return dir;
}
Future<void> fireStoreDeleteFile(String ref) async {
  await fireStorageInstance.ref(ref).delete();
}
Future<String> fireStoreUploadProfilePic(String userId, File imageFile) async {
  Reference storageRef =
      FirebaseStorage.instance.ref().child('profile_pics/$userId.jpg');

  UploadTask uploadTask = storageRef.putFile(imageFile);
  TaskSnapshot snapshot = await uploadTask;

  // Get download URL
  String downloadUrl = await snapshot.ref.getDownloadURL();
  return downloadUrl;
}

// ----------------------------------------------------------------------------
// Firestore Database
// ----------------------------------------------------------------------------
Future fireDbGetSongs(String table) async {
  List Songs = [];

  final CollectionReference fRef = FirebaseFirestore.instance.collection(table);

  try {
    await fRef.get().then((querySnapshot) {
      for (var result in querySnapshot.docs) {
        Songs.add(result.data());
      }
    });

    return Songs;
  } catch (e) {
    print("Firebase DB Error: $e");
    return null;
  }
}
Future fireDbGetUserById(String id) async {
  final CollectionReference fRef =
      FirebaseFirestore.instance.collection(DB_TABLE_USERS);

  try {
    return await fRef.doc(id).get();
  } catch (e) {
    printMsg("Firebase DB Error: $e");
    return null;
  }
}
Future<QuerySnapshot> fireDbSearchUserByEmail(String email) async {
    CollectionReference ref =
        FirebaseFirestore.instance.collection(DB_TABLE_USERS);

    QuerySnapshot querySnapshot =
        await ref.where('email', isEqualTo: email).get();

    return querySnapshot;
}
Future<bool> fireDbcheckIfUserExists(String userId) async {
  final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
      .collection(DB_TABLE_USERS)
      .limit(1)
      .get();

  // Create Collection if it doesn't exist
  if (querySnapshot.docs.isNotEmpty == false) {
    await FirebaseFirestore.instance.collection(DB_TABLE_USERS).add({
      'Dummy': 'Dummy',
    });
    return false;
  }

  // Check User ID
  DocumentReference ref =
      FirebaseFirestore.instance.collection(DB_TABLE_USERS).doc(userId);

  // Check if the document exists
  DocumentSnapshot docSnapshot = await ref.get();
  return docSnapshot.exists;
}
Future<void> fireDbUpdateUserData(User user) async {
  final CollectionReference users =
      FirebaseFirestore.instance.collection(DB_TABLE_USERS);

    await users.doc(user.uid).update({
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoURL,
      'createdDate': FieldValue.serverTimestamp(),
    });

    printMsg('UserData Updated');
}
Future<void> fireDbCreateUser(User user) async {
  final CollectionReference users =
      FirebaseFirestore.instance.collection(DB_TABLE_USERS);

    await users.doc(user.uid).set({
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoURL,
      'createdDate': FieldValue.serverTimestamp(),
    });

    printMsg('UserData Created');
}

// ----------------------------------------------------------------------------
// Firestore Authentication
// ----------------------------------------------------------------------------
class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<AuthResult> fireAuthCreateUserWithEmail(BuildContext context, String email, String password) async {
    try {
      // Create User
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Send Verify Email
      final user = credential.user;
      if (user != null) {
        await user.sendEmailVerification();
      }

      return AuthResult(user: credential.user); credential.user;
    } on FirebaseAuthException catch (e) {
      return AuthResult(exception: e as Exception, code: e.code);
    } catch (e) {
      return AuthResult(exception: e as Exception);
    }
  }
  Future<AuthResult> fireAuthSignOut() async {
    try {
      await _auth.signOut();
      return AuthResult(user: null);
    } catch (e) {
      debugPrint("Firebase Error: ${e}");
      return AuthResult(exception: e as Exception);
    }
  }
  Future<bool> fireAuthResetPassword(BuildContext context, String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint("Firebase Error: ${e.code}");
      return false;
    }
  }
  void fireAuthChangeListner() {
    _auth.userChanges().listen((User? user) {
      if (user == null) {
        print('User is currently signed out!');
      } else {
        print('User Data Changed!');
      }
    });
  }
  void updateDisplayName(String username) {
    try {
      _auth.currentUser!.updateDisplayName(username);
    } catch (e) {
      printMsg("Firebase update username Error: $e");
      MyGlobalMessage.show("Error","Firebase update username: $e");
    }
  }
  void updatePhotoURL(String url) {
    try {
      _auth.currentUser!.updatePhotoURL(url);
    } catch (e) {
      printMsg("Firebase update URL Error: $e");
      MyGlobalMessage.show("Error","Firebase update URL: $e");
    }
  }

  Future<AuthResult> fireAuthSignInWithEmail(BuildContext context, String email, String password) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return AuthResult(user: credential.user);
    }
    on FirebaseAuthException catch (e) {
      return AuthResult(exception: e as Exception, code: e.code);
    } catch (e) {
      return AuthResult(exception: e as Exception);
    }
  }
  Future<AuthResult> signInWithGoogle() async {
    try{
      if (kIsWeb) {
        // Web-specific authentication using popup
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('https://www.googleapis.com/auth/contacts.readonly');
        googleProvider.setCustomParameters({'login_hint': 'user@example.com'});
        UserCredential credential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
        return AuthResult(user: credential.user);
      } else {
        // Mobile authentication (Android & iOS)
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          throw Exception("Google sign-in aborted");
        }

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential credential2 = await FirebaseAuth.instance.signInWithCredential(credential);
        return AuthResult(user: credential2.user);
      }
    }
    on FirebaseAuthException catch (e) {
      return AuthResult(exception: e as Exception, code: e.code);
    } catch (e) {
      return AuthResult(exception: e as Exception);
    }
  }
}

// ----------------------------------------------------------------------------
// Class
// ----------------------------------------------------------------------------
  class AuthResult {
  final User? user;
  final Exception? exception;
  final String? code;


  AuthResult({
    this.user,
    this.exception,
    this.code,

  });

  bool get isSuccess => user != null  && exception == null;
}




