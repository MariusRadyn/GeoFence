import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

class EditProfilePicPage extends StatefulWidget {
  final String? imageURL;
  final String? imageFilename;
  final String docId;
  final String profileType;

  const EditProfilePicPage({
    required this.docId,
    required this.profileType,
    this.imageURL,
    this.imageFilename,
    super.key,
  });

  @override
  State<EditProfilePicPage> createState() => _EditProfilePicPageState();
}

class _EditProfilePicPageState extends State<EditProfilePicPage> {
  String? currentImageUrl;
  String? currentImgFilename;
  bool isLoading = false;
  int _selectedIndex = 0;
  ProfilePicData profilePicData = ProfilePicData(update: false);

  @override
  void initState() {
    super.initState();
    currentImageUrl = widget.imageURL;
    currentImgFilename = widget.imageFilename;
  }

  Future<void> _selectImage({ImageSource? source}) async {
    if (source == null) return;
    final ImagePicker imagePicker = ImagePicker();

    try {
      final XFile? pick = await imagePicker.pickImage(
        source: source,
        imageQuality: 20,
      );

      if (pick == null) return;

      setState(() {
        isLoading = true;
      });

      final bytes = await pick.readAsBytes();
      final thumb = createThumbnail(bytes);
      await _updateImage(thumb);

      setState(() {
        isLoading = false;
      });
    } catch (e, st) {
      setState(() {
        isLoading = false;
      });
      MyGlobalSnackBar.show('Image Error: $e\n$st');
    }
  }

  Future<void> _fireDeleteImage({
    required String filename,
    required String docId,
  }) async {
    try {
      final storagePath = "${widget.profileType}/$docId/$filename";
      await fireStoreDeleteFile(storagePath);
    } catch (e, st) {
      MyGlobalSnackBar.show('Image Error: $e\n$st');
    }
  }

  Future<String> _fireUploadImage({
    required Uint8List bytes,
    required String docId,
  }) async {
    final String name =
        'Image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    profilePicData.imageFilename = name;
    profilePicData.update = true;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child(widget.profileType)
        .child(docId)
        .child(name);

    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
    );

    // putData works on web + mobile; putFile does not work on web.
    await storageRef.putData(bytes, metadata);

    return storageRef.getDownloadURL();
  }

  Uint8List createThumbnail(Uint8List originalBytes) {
    final image = img.decodeImage(originalBytes)!;
    final thumbnail = img.copyResize(image, width: 200);
    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 80));
  }

  Future<void> _updateImage(Uint8List bytes) async {
    if (currentImgFilename != null && currentImgFilename!.isNotEmpty) {
      await _fireDeleteImage(
        filename: currentImgFilename!,
        docId: widget.docId,
      );
    }
    final imgURL = await _fireUploadImage(bytes: bytes, docId: widget.docId);

    setState(() {
      currentImageUrl = imgURL;
      currentImgFilename = profilePicData.imageFilename;
      profilePicData.imageURL = imgURL;
    });
  }

  Future<void> _deleteImage() async {
    if (currentImgFilename == null || currentImgFilename!.isEmpty) return;

    setState(() {
      isLoading = true;
    });
    try {
      await _fireDeleteImage(
        filename: currentImgFilename!,
        docId: widget.docId,
      );

      setState(() {
        currentImageUrl = null;
        currentImgFilename = null;
        profilePicData.imageURL = "";
        profilePicData.imageFilename = "";
        profilePicData.update = true;
        isLoading = false;
      });
    } catch (e) {
      MyGlobalMessage.show('Delete Image: ', '$e', MyMessageType.error);
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle('Profile Picture'),
        leading: IconButton(
          onPressed: () {
            Navigator.pop<ProfilePicData>(context, profilePicData);
          },
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        backgroundColor: colorAppBar,
        unselectedItemColor: Colors.grey,
        selectedItemColor: Colors.grey,
        onTap: (index) async {
          setState(() => _selectedIndex = index);
          if (index == 0) {
            if (kIsWeb) {
              // Camera often unavailable in browsers — fall back to gallery.
              await _selectImage(source: ImageSource.gallery);
            } else {
              await _selectImage(source: ImageSource.camera);
            }
          }
          if (index == 1) await _selectImage(source: ImageSource.gallery);
          if (index == 2) await _deleteImage();
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            label: 'Camera',
            backgroundColor: Colors.grey,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.image),
            label: 'Image',
            backgroundColor: Colors.grey,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.delete_forever),
            label: 'Delete',
            backgroundColor: Colors.grey,
          ),
        ],
      ),
      backgroundColor: colorAppBackground,
      body: isLoading
          ? myProgressCircle()
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: kIsWeb
                    ? NetworkAvatar(
                        imageUrl: currentImageUrl,
                        size: 280,
                        fit: BoxFit.contain,
                      )
                    : Image(
                        image: currentImageUrl != null &&
                                currentImageUrl!.isNotEmpty
                            ? CachedNetworkImageProvider(currentImageUrl!)
                                as ImageProvider
                            : const AssetImage(iconProfile) as ImageProvider,
                        fit: BoxFit.contain,
                        width: 280,
                        height: 280,
                      ),
              ),
            ),
    );
  }
}
