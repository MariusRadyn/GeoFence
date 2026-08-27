import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/shop_image_crop_page.dart';
import 'package:geofence/shop_image_utils.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/shop_spell_check.dart';
import 'package:geofence/utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Developer-only catalog admin for Firestore `shop_products`.
class ShopSetupPage extends StatelessWidget {
  const ShopSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle('Setup Shop'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addShop',
        backgroundColor: colorOrange,
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ShopProductEditPage(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(collectionShopProducts)
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Fallback without orderBy if index/rules block it.
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(collectionShopProducts)
                  .snapshots(),
              builder: (context, snap2) {
                if (snap2.hasError) {
                  return Center(
                    child: MyText(
                      text: 'Could not load shop items:\n${snap2.error}',
                      color: Colors.grey,
                    ),
                  );
                }
                if (!snap2.hasData) {
                  return Center(child: myProgressCircle());
                }
                return _ProductList(docs: snap2.data!.docs);
              },
            );
          }
          if (!snapshot.hasData) {
            return Center(child: myProgressCircle());
          }
          return _ProductList(docs: snapshot.data!.docs);
        },
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  const _ProductList({required this.docs});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return const Center(
        child: MyText(
          text: 'No shop items yet.\nTap + to add one.',
          color: Colors.grey,
        ),
      );
    }

    final money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
    final products = docs
        .map((d) => ShopProduct.fromMap(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final product = products[index];
        return Material(
          color: colorAppBar,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShopProductEditPage(product: product),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: colorAppBar,
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: product.primaryImageUrl != null
                            ? NetworkAvatar(
                                imageUrl: product.primaryImageUrl,
                                size: 64,
                                fit: BoxFit.cover,
                                fallbackAsset: iconShopNoImage,
                              )
                            : Image.asset(
                                iconShopNoImage,
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${money.format(product.salePrice)}'
                          '${product.discount > 0 ? ' · ${product.discount.round()}% off' : ''}'
                          '${product.active ? '' : ' · inactive'}'
                          '${product.isReady ? '' : ' · coming soon'}'
                          '${product.stockCount > 0 ? ' · stock ${product.stockCount}' : ' · no stock'}',
                          style: TextStyle(
                            color: product.active ? colorOrange : Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ShopProductEditPage extends StatefulWidget {
  final ShopProduct? product;

  const ShopProductEditPage({super.key, this.product});

  @override
  State<ShopProductEditPage> createState() => _ShopProductEditPageState();
}

class _ShopProductEditPageState extends State<ShopProductEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final ShopSpellCheckerController _nameController;
  late final ShopSpellCheckerController _descriptionController;
  late final ShopSpellCheckerController _categoryController;
  final _priceController = TextEditingController();
  final _discountController = TextEditingController();
  final _stockCountController = TextEditingController();
  final _weightController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _picker = ImagePicker();

  late String _docId;
  final List<String> _imageUrls = [];
  final List<Uint8List> _pendingBytes = [];
  /// 0.0–1.0 while uploading; empty when idle.
  List<double> _uploadProgress = [];
  bool _active = true;
  bool _freeDelivery = true;
  bool _isReady = false;
  bool _saving = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    ShopSpellCheck.ensureInitialized();
    final p = widget.product;
    _docId = p?.id.isNotEmpty == true
        ? p!.id
        : FirebaseFirestore.instance.collection(collectionShopProducts).doc().id;

    _nameController = ShopSpellCheckerController(text: p?.name ?? '');
    _descriptionController =
        ShopSpellCheckerController(text: p?.description ?? '');
    _categoryController =
        ShopSpellCheckerController(text: p?.category ?? 'Hardware');

    if (p != null) {
      // Always the catalog price from Firestore (unchanged by discount).
      _priceController.text = p.price > 0 ? p.price.toStringAsFixed(2) : '';
      _discountController.text =
          p.discount > 0 ? p.discount.toStringAsFixed(0) : '';
      _stockCountController.text =
          p.stockCount > 0 ? p.stockCount.toString() : '';
      _weightController.text = p.weightKg.toString();
      _lengthController.text = p.lengthCm.toString();
      _widthController.text = p.widthCm.toString();
      _heightController.text = p.heightCm.toString();
      _imageUrls.addAll(p.imageUrls);
      _active = p.active;
      _freeDelivery = p.freeDelivery;
      _isReady = p.isReady;
    } else {
      _stockCountController.text = '0';
      _weightController.text = '1';
      _lengthController.text = '20';
      _widthController.text = '15';
      _heightController.text = '10';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _categoryController.dispose();
    _stockCountController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 92,
      );
      if (files.isEmpty) return;
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final normalized = normalizeShopImageBytesCenterCrop(bytes);
        if (normalized != null) _pendingBytes.add(normalized);
      }
      if (mounted) setState(() {});
    } catch (e) {
      MyGlobalSnackBar.show('Gallery error: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      if (kIsWeb) {
        await _pickFromGallery();
        return;
      }
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (file == null) return;
      if (!mounted) return;
      final bytes = await file.readAsBytes();
      final cropped = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => ShopImageCropPage(imageBytes: bytes),
        ),
      );
      if (cropped == null) return;
      setState(() => _pendingBytes.add(cropped));
    } catch (e) {
      MyGlobalSnackBar.show('Camera error: $e');
    }
  }

  Future<List<String>> _uploadPendingImages() async {
    if (_pendingBytes.isEmpty) return const [];

    // Show a frame + progress ring for every pending photo immediately.
    _uploadProgress = List<double>.filled(_pendingBytes.length, 0.0);
    if (mounted) setState(() {});

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final results = List<String?>.filled(_pendingBytes.length, null);

    await Future.wait(List.generate(_pendingBytes.length, (i) async {
      final bytes = _pendingBytes[i];
      final name = 'Image_${stamp}_$i.jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child(collectionShopProducts)
          .child(_docId)
          .child(name);
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      task.snapshotEvents.listen((snap) {
        if (!mounted || i >= _uploadProgress.length) return;
        final total = snap.totalBytes;
        final progress =
            total > 0 ? snap.bytesTransferred / total : 0.0;
        setState(() {
          _uploadProgress[i] = progress.clamp(0.0, 1.0);
        });
      });
      await task;
      results[i] = await ref.getDownloadURL();
      if (mounted && i < _uploadProgress.length) {
        setState(() => _uploadProgress[i] = 1.0);
      }
    }));

    return results.whereType<String>().toList();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final discount = double.tryParse(_discountController.text.trim()) ?? 0;
    final stockCount = int.tryParse(_stockCountController.text.trim()) ?? 0;
    if (discount < 0 || discount >= 100) {
      MyGlobalSnackBar.show('Discount must be between 0 and 99');
      return;
    }

    final category = _categoryController.text.trim().isEmpty
        ? 'General'
        : _categoryController.text.trim();
    final spellingIssues = await ShopSpellCheck.checkFields(
      name: name,
      description: description,
      category: category,
    );
    if (!mounted) return;
    final proceed = await ShopSpellCheck.confirmIfNeeded(
      context,
      spellingIssues,
    );
    if (!proceed) return;

    setState(() {
      _saving = true;
      if (_pendingBytes.isNotEmpty) {
        _uploadProgress = List<double>.filled(_pendingBytes.length, 0.0);
      }
    });
    try {
      final newUrls = await _uploadPendingImages();
      final allUrls = [..._imageUrls, ...newUrls];

      // Keep catalog [price] intact in Firestore. Discount is separate;
      // sale price is computed in the app when discount > 0.
      final product = ShopProduct(
        id: _docId,
        name: name,
        description: description,
        price: price,
        discount: discount,
        imageUrl: allUrls.isNotEmpty ? allUrls.first : null,
        imageUrls: allUrls,
        category: category,
        freeDelivery: _freeDelivery,
        active: _active,
        stockCount: stockCount < 0 ? 0 : stockCount,
        isReady: _isReady,
        weightKg: double.tryParse(_weightController.text.trim()) ?? 1,
        lengthCm: double.tryParse(_lengthController.text.trim()) ?? 20,
        widthCm: double.tryParse(_widthController.text.trim()) ?? 15,
        heightCm: double.tryParse(_heightController.text.trim()) ?? 10,
      );

      await FirebaseFirestore.instance
          .collection(collectionShopProducts)
          .doc(_docId)
          .set({
        ...product.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (!_isEditing) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      MyGlobalSnackBar.show('Shop item saved');
      Navigator.pop(context);
    } catch (e) {
      MyGlobalSnackBar.show('Save failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadProgress = [];
        });
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorAppTitle,
        title: const MyText(text: 'Delete item?', color: Colors.white),
        content: const MyText(
          text: 'This removes the product from the shop catalog.',
          color: Colors.grey,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const MyText(text: 'Cancel', color: Colors.white70),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const MyText(text: 'Delete', color: Colors.redAccent),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection(collectionShopProducts)
          .doc(_docId)
          .delete();
      if (!mounted) return;
      MyGlobalSnackBar.show('Item deleted');
      Navigator.pop(context);
    } catch (e) {
      MyGlobalSnackBar.show('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalImages = _imageUrls.length + _pendingBytes.length;

    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle(_isEditing ? 'Edit Shop Item' : 'Add Shop Item'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
              key: _formKey,
              child: AbsorbPointer(
                absorbing: _saving,
                child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  const MyText(
                    text: 'Photos',
                    fontsize: 14,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 96,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ...List.generate(_imageUrls.length, (i) {
                          return _ImageThumb(
                            url: _imageUrls[i],
                            onRemove: _saving
                                ? null
                                : () => setState(() => _imageUrls.removeAt(i)),
                          );
                        }),
                        ...List.generate(_pendingBytes.length, (i) {
                          final progress = i < _uploadProgress.length
                              ? _uploadProgress[i]
                              : null;
                          return _ImageThumb(
                            bytes: _pendingBytes[i],
                            uploadProgress: progress,
                            onRemove: _saving
                                ? null
                                : () => setState(
                                      () => _pendingBytes.removeAt(i),
                                    ),
                          );
                        }),
                        if (!_saving) ...[
                          _AddPhotoButton(
                            label: 'Gallery',
                            icon: Icons.photo_library_outlined,
                            onTap: _pickFromGallery,
                          ),
                          _AddPhotoButton(
                            label: kIsWeb ? 'Files' : 'Camera',
                            icon: kIsWeb
                                ? Icons.upload_file
                                : Icons.photo_camera_outlined,
                            onTap: _pickFromCamera,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 14),
                    child: Text(
                      _saving && _pendingBytes.isNotEmpty
                          ? 'Uploading ${_pendingBytes.length} photo${_pendingBytes.length == 1 ? '' : 's'}…'
                          : totalImages == 0
                              ? 'Add one or more photos'
                              : '$totalImages photo${totalImages == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: _saving ? colorOrange : Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  MyTextFormField(
                    controller: _nameController,
                    labelText: 'Item name',
                    hintText: 'e.g. Distance Wheel',
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  MyTextFormField(
                    controller: _descriptionController,
                    labelText: 'Description',
                    hintText: 'Short product description',
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                    maxLines: 6,
                    minLines: 4,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  MyTextFormField(
                    controller: _priceController,
                    labelText: 'Price (ZAR)',
                    hintText: 'Catalog price (not changed by discount)',
                    inputType:
                        const TextInputType.numberWithOptions(decimal: true),
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n < 0) return 'Enter a valid price';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  MyTextFormField(
                    controller: _discountController,
                    labelText: 'Discount (%)',
                    hintText: 'e.g. 20 — set 0 when special ends',
                    inputType:
                        const TextInputType.numberWithOptions(decimal: true),
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = double.tryParse(v.trim());
                      if (n == null || n < 0 || n >= 100) {
                        return 'Use 0–99';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  MyTextFormField(
                    controller: _categoryController,
                    labelText: 'Category',
                    hintText: 'Hardware / Kits / Services',
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(height: 10),
                  MyTextFormField(
                    controller: _stockCountController,
                    labelText: 'Stock count',
                    hintText: 'Units available for sale',
                    inputType: TextInputType.number,
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 0) return 'Enter 0 or more';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  MyTextFormField(
                    controller: _weightController,
                    labelText: 'Weight (kg)',
                    hintText: 'Used for Bob Go rates',
                    inputType:
                        const TextInputType.numberWithOptions(decimal: true),
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(height: 10),
                  MyTextFormField(
                    controller: _lengthController,
                    labelText: 'Length (cm)',
                    inputType:
                        const TextInputType.numberWithOptions(decimal: true),
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(height: 10),
                  MyTextFormField(
                    controller: _widthController,
                    labelText: 'Width (cm)',
                    inputType:
                        const TextInputType.numberWithOptions(decimal: true),
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(height: 10),
                  MyTextFormField(
                    controller: _heightController,
                    labelText: 'Height (cm)',
                    inputType:
                        const TextInputType.numberWithOptions(decimal: true),
                    backgroundColor: colorAppBar,
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const MyText(text: 'Launched (ready to buy)'),
                    subtitle: const MyText(
                      text: 'Off shows Coming Soon on shop tiles',
                      color: Colors.white54,
                      fontsize: 12,
                    ),
                    value: _isReady,
                    activeThumbColor: colorOrange,
                    onChanged: (v) => setState(() => _isReady = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const MyText(text: 'Active in shop'),
                    value: _active,
                    activeThumbColor: colorOrange,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const MyText(text: 'Free delivery'),
                    value: _freeDelivery,
                    activeThumbColor: colorOrange,
                    onChanged: (v) => setState(() => _freeDelivery = v),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      child: Text(
                        _saving ? 'Uploading…' : 'Save',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  final String? url;
  final Uint8List? bytes;
  final VoidCallback? onRemove;
  /// null = not uploading; 0–1 = upload progress.
  final double? uploadProgress;

  const _ImageThumb({
    this.url,
    this.bytes,
    this.onRemove,
    this.uploadProgress,
  });

  @override
  Widget build(BuildContext context) {
    final uploading = uploadProgress != null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                width: 88,
                height: 88,
                child: bytes != null
                    ? Image.memory(bytes!, fit: BoxFit.cover)
                    : NetworkAvatar(
                        imageUrl: url,
                        size: 88,
                        fit: BoxFit.cover,
                        fallbackAsset: iconShopNoImage,
                      ),
              ),
            ),
          ),
          if (uploading)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        value: uploadProgress! <= 0
                            ? null
                            : uploadProgress!.clamp(0.0, 1.0),
                        strokeWidth: 3,
                        color: colorOrange,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (onRemove != null)
            Positioned(
              right: 2,
              top: 2,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _AddPhotoButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: colorAppBar,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colorOrange),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
