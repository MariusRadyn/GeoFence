import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/shop_product_image.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ShopReview {
  final String id;
  final String userId;
  final String userName;
  final double rating;
  final String comment;
  final DateTime? createdAt;

  const ShopReview({
    required this.id,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    this.createdAt,
  });

  factory ShopReview.fromMap(Map<String, dynamic> map, String id) {
    final ts = map['createdAt'];
    return ShopReview(
      id: id,
      userId: '${map['userId'] ?? ''}',
      userName: '${map['userName'] ?? 'Customer'}',
      rating: (map['rating'] is num)
          ? (map['rating'] as num).toDouble()
          : double.tryParse('${map['rating']}') ?? 0,
      comment: '${map['comment'] ?? ''}',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class ShopProductDetailPage extends StatefulWidget {
  final ShopProduct product;

  const ShopProductDetailPage({super.key, required this.product});

  @override
  State<ShopProductDetailPage> createState() => _ShopProductDetailPageState();
}

class _ShopProductDetailPageState extends State<ShopProductDetailPage> {
  final _money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
  final _reviewController = TextEditingController();
  final _pageController = PageController();

  int _selectedImage = 0;
  double _reviewStars = 5;
  bool _submitting = false;

  ShopProduct get product {
    final matches = context
        .watch<ShopCatalogService>()
        .products
        .where((p) => p.id == widget.product.id);
    return matches.isEmpty ? widget.product : matches.first;
  }

  List<String> get _images {
    final urls = product.imageUrls;
    if (urls.isNotEmpty) return urls;
    final primary = product.primaryImageUrl;
    if (primary != null && primary.isNotEmpty) return [primary];
    return const [];
  }

  CollectionReference<Map<String, dynamic>> get _reviewsRef =>
      FirebaseFirestore.instance
          .collection(collectionShopProducts)
          .doc(widget.product.id)
          .collection(collectionShopReviews);

  @override
  void dispose() {
    _reviewController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      MyGlobalMessage.show(
        'Login required',
        'Please log in to leave a review.',
        MyMessageType.warning,
      );
      return;
    }

    final comment = _reviewController.text.trim();
    if (comment.isEmpty) {
      MyGlobalSnackBar.show('Please write a short review');
      return;
    }

    setState(() => _submitting = true);
    try {
      final userName = context.read<UserDataService>().userdata?.displayName;
      final name = (userName != null && userName.trim().isNotEmpty)
          ? userName.trim()
          : (user.email ?? 'Customer');

      // One review per user — upsert by uid.
      await _reviewsRef.doc(user.uid).set({
        'userId': user.uid,
        'userName': name,
        'rating': _reviewStars,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Keep catalog aggregate in sync (best-effort; UI uses live reviews).
      try {
        await _recalculateProductRating(
          uid: user.uid,
          latestRating: _reviewStars,
        );
      } catch (e) {
        printDebugMsg('Rating aggregate update failed: $e');
      }

      _reviewController.clear();
      if (mounted) {
        setState(() => _reviewStars = 5);
        MyGlobalSnackBar.show('Thanks for your review');
      }
    } catch (e) {
      MyGlobalSnackBar.show('Could not save review: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Recomputes product.rating / reviewCount from the reviews subcollection.
  /// [uid] + [latestRating] are merged in so a just-written review is never missed.
  Future<void> _recalculateProductRating({
    String? uid,
    double? latestRating,
  }) async {
    final snap = await _reviewsRef.get();
    final byUser = <String, double>{};
    for (final doc in snap.docs) {
      final r = doc.data()['rating'];
      byUser[doc.id] = (r is num) ? r.toDouble() : 0;
    }
    if (uid != null && latestRating != null) {
      byUser[uid] = latestRating;
    }

    if (byUser.isEmpty) {
      await FirebaseFirestore.instance
          .collection(collectionShopProducts)
          .doc(widget.product.id)
          .update({
        'rating': 0,
        'reviewCount': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final sum = byUser.values.fold<double>(0, (a, b) => a + b);
    final avg = sum / byUser.length;

    await FirebaseFirestore.instance
        .collection(collectionShopProducts)
        .doc(widget.product.id)
        .update({
      'rating': double.parse(avg.toStringAsFixed(1)),
      'reviewCount': byUser.length,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Widget _buildMainImage(String? url) {
    return AspectRatio(
      aspectRatio: 1,
      child: ColoredBox(
        color: (url != null && url.isNotEmpty)
            ? Colors.white.withValues(alpha: 0.95)
            : colorAppBar,
        child: ShopProductImage(imageUrl: url),
      ),
    );
  }

  Widget _buildGallery() {
    final images = _images;
    if (images.isEmpty) {
      return _buildMainImage(null);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final mainSide = math.min(constraints.maxWidth - 80, 420.0);
        return SizedBox(
          height: mainSide,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 72,
                child: ListView.separated(
                  padding: const EdgeInsets.only(right: 8),
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final selected = i == _selectedImage;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedImage = i);
                        _pageController.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? colorOrange : Colors.white24,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ShopProductImage(
                          imageUrl: images[i],
                          side: 64,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _selectedImage = i),
                    itemBuilder: (_, i) => _buildMainImage(images[i]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = product;
    final cart = context.watch<ShopCartService>();

    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle(p.name),
        actions: [
          if (cart.itemCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${cart.itemCount} in basket',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    p.isReady && p.stockCount > 0 ? colorOrange : Colors.white24,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: p.isReady && p.stockCount > 0
                  ? () {
                      cart.add(p);
                      MyGlobalSnackBar.show('${p.name} added to basket');
                    }
                  : () {
                      MyGlobalSnackBar.show(
                        !p.isReady
                            ? '${p.name} is coming soon'
                            : '${p.name} is out of stock',
                      );
                    },
              icon: Icon(
                !p.isReady
                    ? Icons.schedule
                    : p.stockCount > 0
                        ? Icons.add_shopping_cart
                        : Icons.remove_shopping_cart,
              ),
              label: Text(
                !p.isReady
                    ? 'Coming Soon'
                    : p.stockCount > 0
                        ? 'Add to Cart · ${_money.format(p.salePrice)}'
                        : 'Out of Stock',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _buildGallery(),
          if (_images.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Photo ${_selectedImage + 1} of ${_images.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),

          Text(
            p.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _LiveOverallRating(reviewsRef: _reviewsRef, fallback: p),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money.format(p.salePrice),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (p.hasDeal) ...[
                const SizedBox(width: 10),
                Text(
                  _money.format(p.price),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 15,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.white38,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorOrange,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '-${p.savePercent}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (p.hasDeal)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Catalog price ${_money.format(p.price)} · ${p.discount.round()}% discount applied',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: p.category, icon: Icons.category_outlined),
              if (p.freeDelivery)
                const _InfoChip(
                  label: 'FREE DELIVERY',
                  icon: Icons.local_shipping_outlined,
                  color: Color(0xFF4ADE80),
                ),
              _InfoChip(
                label: !p.isReady
                    ? 'Coming soon'
                    : p.stockCount > 0
                        ? '${p.stockCount} in stock'
                        : 'Out of stock',
                icon: !p.isReady
                    ? Icons.schedule
                    : p.stockCount > 0
                        ? Icons.check_circle_outline
                        : Icons.block,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Description',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            p.description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.45,
            ),
          ),

          const SizedBox(height: 24),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          const Text(
            'Customer reviews',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),

          // Write a review
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorAppBar,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rate this product',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (i) {
                    final star = i + 1.0;
                    return IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36),
                      onPressed: () => setState(() => _reviewStars = star),
                      icon: Icon(
                        star <= _reviewStars ? Icons.star : Icons.star_border,
                        color: colorOrange,
                        size: 30,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _reviewController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Share your experience with this product…',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                    filled: true,
                    fillColor: colorAppBackground.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorOrange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _submitting ? null : _submitReview,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Submit review'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _reviewsRef.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Could not load reviews: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final reviews = snapshot.data!.docs
                  .map((d) => ShopReview.fromMap(d.data(), d.id))
                  .toList()
                ..sort((a, b) {
                  final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return bAt.compareTo(aAt);
                });
              return _ReviewsList(reviews: reviews);
            },
          ),
        ],
      ),
    );
  }
}

class _LiveOverallRating extends StatelessWidget {
  final CollectionReference<Map<String, dynamic>> reviewsRef;
  final ShopProduct fallback;

  const _LiveOverallRating({
    required this.reviewsRef,
    required this.fallback,
  });

  static (double avg, int count) _fromReviews(List<ShopReview> reviews) {
    if (reviews.isEmpty) return (0, 0);
    final sum = reviews.fold<double>(0, (a, r) => a + r.rating);
    return (sum / reviews.length, reviews.length);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: reviewsRef.snapshots(),
      builder: (context, snapshot) {
        double avg = fallback.rating;
        int count = fallback.reviewCount;

        if (snapshot.hasData) {
          final reviews = snapshot.data!.docs
              .map((d) => ShopReview.fromMap(d.data(), d.id))
              .toList();
          final computed = _fromReviews(reviews);
          avg = computed.$1;
          count = computed.$2;
        }

        return Row(
          children: [
            ...List.generate(5, (i) {
              final threshold = i + 1.0;
              final IconData icon;
              if (avg >= threshold) {
                icon = Icons.star;
              } else if (avg >= threshold - 0.5) {
                icon = Icons.star_half;
              } else {
                icon = Icons.star_border;
              }
              return Icon(icon, size: 18, color: colorOrange);
            }),
            const SizedBox(width: 8),
            Text(
              count == 0
                  ? 'No reviews yet'
                  : '${avg.toStringAsFixed(1)} ($count review${count == 1 ? '' : 's'})',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _InfoChip({
    required this.label,
    required this.icon,
    this.color = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorAppBar,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ReviewsList extends StatelessWidget {
  final List<ShopReview> reviews;

  const _ReviewsList({required this.reviews});

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No reviews yet. Be the first to review this product.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final dateFmt = DateFormat('dd MMM yyyy');
    return Column(
      children: reviews.map((r) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorAppBar,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: colorTileLight,
                    child: Text(
                      r.userName.isNotEmpty ? r.userName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (r.createdAt != null)
                          Text(
                            dateFmt.format(r.createdAt!),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: List.generate(5, (i) {
                      return Icon(
                        i < r.rating.round() ? Icons.star : Icons.star_border,
                        size: 14,
                        color: colorOrange,
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                r.comment,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
