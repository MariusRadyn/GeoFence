import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:image_picker/image_picker.dart';

class EditProfilePicPage extends StatefulWidget {
  final String? image;
  final String? currentImagePath;

  const EditProfilePicPage({
    this.image,
    this.currentImagePath,
    super.key
  });

  @override
  State<EditProfilePicPage> createState() => _EditProfilePicPageState();
}

class _EditProfilePicPageState extends State<EditProfilePicPage> {
  final ImagePicker picker = ImagePicker();
  XFile? selectedImage;
  Uint8List? selectedImageBytes;


  @override
  void initState() {
    if(widget.image != null){
      selectedImage = XFile(widget.image!);
    }
    super.initState();
  }

  @override
  /// This triggers when the user presses the app bar back button.
  Future<bool> _onWillPop() async {
    Navigator.pop(context, selectedImage);
    return false; // prevents default pop, since we already popped manually
  }

  Future<void> selectImage({ImageSource? source}) async {
    if (source == null) return;
    final ImagePicker imagePicker = ImagePicker();

    try {
      final XFile? pick = await picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pick == null) return;

      // Check if the path points to a real file first
      final file = File(pick.path);
      final exists = await file.exists();

      if (!exists) {
        // Fallback: read bytes (works for Google Photos, virtual files, etc.)
        final bytes = await pick.readAsBytes();
        setState(() {
          // Keep both, so UI can render either way
          selectedImage = pick;           // still keep the reference
          selectedImageBytes = bytes;     // Uint8List? in your State
        });
      } else {
        setState(() {
          selectedImage = pick;
          selectedImageBytes = null; // Not needed, we have a real file
        });
      }
    } catch (e, st) {
      MyGlobalSnackBar.show('Image failed: $e\n$st');
    }

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
      widget.currentImagePath ?? IMAGE_PROFILE,
      width: double.infinity,
      fit: BoxFit.fitWidth,
    );
  }


  Future<void> uploadToFirebase(XFile pick) async {
    // final ref = FirebaseStorage.instance
    //     .ref()
    //     .child('profile_pics/${user.uid}.jpg');
    //
    // try {
    //   // Prefer bytes
    //   final data = await pick.readAsBytes();
    //   final metadata = SettableMetadata(contentType: 'image/jpeg');
    //   await ref.putData(data, metadata);
    //
    //   final url = await ref.getDownloadURL();
    //   await FirebaseFirestore.instance
    //       .collection('users')
    //       .doc(user.uid)
    //       .update({'photoUrl': url});
    // } catch (e) {
    //   // Fallback to file if needed
    //   final file = File(pick.path);
    //   if (await file.exists()) {
    //     await ref.putFile(file);
    //     final url = await ref.getDownloadURL();
    //     await FirebaseFirestore.instance
    //         .collection('users')
    //         .doc(user.uid)
    //         .update({'photoUrl': url});
    //   } else {
    //     rethrow;
    //   }
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,
        title: MyAppbarTitle('Profile Picture'),
      ),
      backgroundColor: APP_BACKGROUND_COLOR,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
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

          FloatingActionButton(
            heroTag: "heroSelectImage",
            backgroundColor: COLOR_ORANGE,
            foregroundColor: Colors.white,
            onPressed: (){
              selectImage(source:  ImageSource.gallery);
            },
            child: Icon(Icons.image),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _imagePreview(),
        ),
      ),
    );
  }
}
