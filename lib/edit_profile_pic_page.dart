import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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

  Future<File?> _selectImage({ImageSource? source}) async {
    if (source == null) return null;
    final ImagePicker imagePicker = ImagePicker();

    try {
      final XFile? pick = await imagePicker.pickImage(
        source: source,
        imageQuality: 20,
      );

      if (pick == null) return null;
      final thumb = await pick.readAsBytes();

      setState(() {
        isLoading = true;
      });


      final dir = await getTemporaryDirectory();
      final filePath = path.join(dir.path, 'image.jpg');
      final file = File(filePath);
      await file.writeAsBytes(thumb, flush: true);

      await _updateImage(file);

      setState(() {
        isLoading = false;
      });

      return file;

    } catch (e, st) {
      MyGlobalSnackBar.show('Image Error: $e\n$st');
    }
    return null;
  }
  Future<void> _fireDeleteImage({required String filename,required String docId}) async {
    try{
      String path = "${widget.profileType}/$docId/$filename";
      await fireStoreDeleteFile(path);
    }
    catch (e, st) {
      MyGlobalSnackBar.show('Image Error: $e\n$st');
    }
  }
  Future<String> _fireUploadImage({required File image,required String docId}) async {
    final String name ='Image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    profilePicData.imageFilename = name;
    profilePicData.update = true;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child(widget.profileType)
        .child(docId)
        .child(name);

    final metadata = SettableMetadata(
      contentType: 'image/jpg',
    );

    await storageRef.putFile(image, metadata);

    // ✅ Get download URL
    final downloadUrl = await storageRef.getDownloadURL();
    return downloadUrl;
  }
  Uint8List createThumbnail(Uint8List originalBytes) {
    final image = img.decodeImage(originalBytes)!;

    // Resize to max 200px (keeps aspect ratio)
    final thumbnail = img.copyResize(
      image,
      width: 200,
    );

    return Uint8List.fromList(
      img.encodeJpg(thumbnail, quality: 80),
    );
  }
  Future<void> _updateImage(File file) async {

    if (currentImgFilename != null && currentImgFilename!.isNotEmpty) {
      await _fireDeleteImage(filename: currentImgFilename!, docId: widget.docId);
    }
    final imgURL = await _fireUploadImage(image: file, docId: widget.docId);

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
        profilePicData.update = true; // ✅ Tell the previous screen to update DB
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
        title: MyAppbarTitle('Profile Picture'),
        leading: IconButton(
            onPressed: () {
              Navigator.pop<ProfilePicData>(context, profilePicData);
            },
            icon: const Icon(Icons.arrow_back),
        )
      ),
      bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          backgroundColor: colorAppBar,
          unselectedItemColor: Colors.grey,
          selectedItemColor: Colors.grey,
          onTap: (index) async {
            setState(() => _selectedIndex = index);
            if(index == 0) await _selectImage(source:  ImageSource.camera);
            if(index == 1) await _selectImage(source:  ImageSource.gallery);
            if(index == 2) await _deleteImage();
          },
          items: [
            // Add Button
            BottomNavigationBarItem(
                icon: Icon(Icons.camera_alt_outlined),
                label: 'Camera',
                backgroundColor: Colors.grey
            ),

            // Image Button
            BottomNavigationBarItem(
              icon: Icon(Icons.image),
              label: 'Image',
              backgroundColor: Colors.grey,
            ),

            // Delete Button
            BottomNavigationBarItem(
              icon: Icon(Icons.delete_forever),
              label: 'Delete',
              backgroundColor: Colors.grey,
            ),

          ]
      ),
      backgroundColor: colorAppBackground,
      body: isLoading
          ? MyProgressCircle()
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Image(
                  image: currentImageUrl != null && currentImageUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(currentImageUrl!) as ImageProvider
                      : AssetImage(iconProfile) as ImageProvider,
                  fit: BoxFit.contain, // ✅ shows entire image
                ),
              ),
            ),
    );
  }
}
