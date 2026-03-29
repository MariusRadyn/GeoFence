import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class EditProfilePicPage extends StatefulWidget {
  String? image;
  final String docId;
  final String profileType;

  EditProfilePicPage({
    required this.docId,
    required this.profileType,
    this.image,
    super.key
  });

  @override
  State<EditProfilePicPage> createState() => _EditProfilePicPageState();
}

class _EditProfilePicPageState extends State<EditProfilePicPage> {
  XFile? selectedImage;
  Uint8List? selectedImageBytes;

  @override
  void initState() {
    if(widget.image != null){
      selectedImage = XFile(widget.image!);
    }
    super.initState();
  }

  Future<File?> _selectImage({ImageSource? source}) async {
    if (source == null) return null;
    final ImagePicker imagePicker = ImagePicker();

    try {
      final XFile? pick = await imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pick == null) return null;
      final bytes = await pick.readAsBytes();

      setState(() {
        selectedImageBytes = bytes;
      });

      final dir = await getTemporaryDirectory();
      final filePath = path.join(dir.path, 'image.png');
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      return file;

    } catch (e, st) {
      MyGlobalSnackBar.show('Image failed: $e\n$st');
    }
    return null;
  }
  Widget _imagePreview() {
    // 1 — New image selected as bytes
    if (selectedImageBytes != null) {
      return Image.memory(
        selectedImageBytes!,
        width: double.infinity,
        fit: BoxFit.fitWidth,
      );
    }

    // 2 — New image selected as file
    if (selectedImage != null && selectedImage!.path.isNotEmpty) {
      return Image.file(
        File(selectedImage!.path),
        width: double.infinity,
        fit: BoxFit.fitWidth,
      );
    }

    // 3 — Default asset
    return Image.asset(
      widget.image ?? IMAGE_PROFILE,
      width: double.infinity,
      fit: BoxFit.fitWidth,
    );
  }
  Future<String> _fireUploadImage({
    required File image,
    required String docId,
  }) async {
    final String name ='Image_${DateTime.now().millisecondsSinceEpoch}.png';

    final storageRef = FirebaseStorage.instance
        .ref()
        .child(widget.profileType)
        .child(docId)
        .child(name);

    final metadata = SettableMetadata(
      contentType: 'image/png',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,
        title: MyAppbarTitle('Profile Picture'),
        leading: IconButton(
            onPressed: (){
              Navigator.pop(context, widget.image);
            },
            icon: const Icon(Icons.arrow_back),
        )

      ),
      backgroundColor: APP_BACKGROUND_COLOR,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [

          // Camera
          FloatingActionButton(
            heroTag: "heroCamera",
              backgroundColor: COLOR_ORANGE,
              foregroundColor: Colors.white,
              onPressed: (){
                // Navigator.push(
                //   context,
                //   MaterialPageRoute(
                //     builder: (context) => OperatorEditPage(
                //       operatorData: context.read<OperatorService>().newOperator,
                //     ),
                //   ),
                //);
              },
              child: Icon(Icons.camera_alt_outlined),
          ),

          SizedBox(height: 10),

          // Select Image
          FloatingActionButton(
            heroTag: "heroSelectImage",
            backgroundColor: COLOR_ORANGE,
            foregroundColor: Colors.white,
            onPressed: () async {
              File? file = await _selectImage(source:  ImageSource.gallery);
              if(file!=null){
                widget.image = await _fireUploadImage(image: file, docId: widget.docId);
              }
            },

            child: Icon(Icons.image),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
          Image(
            image: widget.image == null
                ? AssetImage(IMAGE_PROFILE) as ImageProvider
                : CachedNetworkImageProvider(widget.image!),
            fit: BoxFit.contain, // ✅ shows entire image
          ),

        ),
      ),
    );
  }
}
