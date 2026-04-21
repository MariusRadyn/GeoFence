import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class EditProfilePicPage extends StatefulWidget {
  String? imageURL;
  String? imageFilename;
  final String docId;
  final String profileType;

  EditProfilePicPage({
    required this.docId,
    required this.profileType,
    this.imageURL,
    this.imageFilename,
    super.key
  });

  @override
  State<EditProfilePicPage> createState() => _EditProfilePicPageState();
}

class _EditProfilePicPageState extends State<EditProfilePicPage> {
  String? oldImgFilename;
  bool isLoading = false;
  ProfilePicData profilePicData = ProfilePicData(update: false);

  @override
  void initState() {
    if(widget.imageFilename != null){
      oldImgFilename = widget.imageFilename!;
    }
    super.initState();
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

      });

      final dir = await getTemporaryDirectory();
      final filePath = path.join(dir.path, 'image.jpg');
      final file = File(filePath);
      await file.writeAsBytes(thumb, flush: true);
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
    setState(() {
      isLoading = true;
    });

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

    setState(() {
      isLoading = false;
    });
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
      if(oldImgFilename!= null && oldImgFilename!.isNotEmpty) {
        await _fireDeleteImage(filename: oldImgFilename!, docId: widget.docId);
      }
      final imgURL = await _fireUploadImage(image: file, docId: widget.docId);

      setState(()  {
        widget.imageURL = imgURL;
        oldImgFilename = profilePicData.imageFilename;
        profilePicData.imageURL = imgURL;
      });
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
      backgroundColor: colorAppBackground,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [

          // Camera
          FloatingActionButton(
            heroTag: "heroCamera",
              backgroundColor: colorOrange,
              foregroundColor: Colors.white,
            onPressed: () async {
              File? file = await _selectImage(source:  ImageSource.camera);
              if(file!=null){
               await _updateImage(file);
              }
            },

            child: Icon(Icons.camera_alt_outlined),
          ),

          SizedBox(height: 10),

          // Select Image
          FloatingActionButton(
            heroTag: "heroSelectImage",
            backgroundColor: colorOrange,
            foregroundColor: Colors.white,
            onPressed: () async {
              File? file = await _selectImage(source:  ImageSource.gallery);
              if(file!=null){
                await _updateImage(file);
              }
            },

            child: Icon(Icons.image),
          ),
        ],
      ),
      body: isLoading ?  MyProgressCircle(): Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
          Image(
            image: widget.imageURL != null && widget.imageURL!.isNotEmpty
                ? CachedNetworkImageProvider(widget.imageURL!) as ImageProvider
                : AssetImage(imageProfile) as ImageProvider,
            fit: BoxFit.contain, // ✅ shows entire image
          ),

        ),
      ),
    );
  }
}
