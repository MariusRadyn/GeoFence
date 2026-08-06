import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/shop_product_detail_page.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

const String collectionShopProducts = 'shop_products';
const String collectionShopOrders = 'shop_orders';
const String collectionShopReviews = 'reviews';

/// Catalog item for the Limitless online shop.
class ShopProduct {
  final String id;
  final String name;
  final String description;
  final double price;
  final double? listPrice;
  final double discount;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? imageAsset;
  final String category;
  final double rating;
  final int reviewCount;
  final bool freeDelivery;
  final bool active;
  final int stockCount;
  /// When false, product is visible but not yet launched for purchase.
  final bool isReady;

  const ShopProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.listPrice,
    this.discount = 0,
    this.imageUrl,
    this.imageUrls = const [],
    this.imageAsset,
    this.category = 'General',
    this.rating = 0,
    this.reviewCount = 0,
    this.freeDelivery = true,
    this.active = true,
    this.stockCount = 0,
    this.isReady = true,
  });

  String? get primaryImageUrl {
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) return imageUrl;
    if (imageUrls.isNotEmpty) return imageUrls.first;
    return null;
  }
  bool get hasDeal => discount > 0 && discount < 100;
  double get salePrice =>
      hasDeal ? price * (1 - discount / 100) : price;
  int? get savePercent => hasDeal ? discount.round().clamp(1, 99) : null;

  factory ShopProduct.fromMap(Map<String, dynamic> map, String id) {
    double asDouble(dynamic v, [double fallback = 0]) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    int asInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    final rawUrls = map['imageUrls'];
    final urls = <String>[];
    if (rawUrls is List) {
      for (final u in rawUrls) {
        final s = u?.toString().trim() ?? '';
        if (s.isNotEmpty) urls.add(s);
      }
    }

    final single = map['imageUrl']?.toString();
    if (single != null &&
        single.trim().isNotEmpty &&
        !urls.contains(single.trim())) {
      urls.insert(0, single.trim());
    }

    return ShopProduct(
      id: id,
      name: '${map['name'] ?? ''}',
      description: '${map['description'] ?? ''}',
      // Always the real catalog price — never overwritten by discount.
      price: asDouble(map['price']),
      listPrice: map['listPrice'] == null ? null : asDouble(map['listPrice']),
      discount: asDouble(map['discount']),
      imageUrl: urls.isNotEmpty ? urls.first : single,
      imageUrls: urls,
      imageAsset: map['imageAsset']?.toString(),
      category: '${map['category'] ?? 'General'}',
      // Prefer stored aggregate; default 0 so unset products don't look like 5★.
      rating: asDouble(map['rating']),
      reviewCount: asInt(map['reviewCount']),
      freeDelivery: map['freeDelivery'] != false,
      active: map['active'] != false,
      stockCount: asInt(map['stockCount']),
      isReady: map['isReady'] != false,
    );
  }
  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'price': price,
        'listPrice': listPrice,
        'discount': discount,
        'imageUrl': primaryImageUrl,
        'imageUrls': imageUrls,
        'imageAsset': imageAsset,
        'category': category,
        'rating': rating,
        'reviewCount': reviewCount,
        'freeDelivery': freeDelivery,
        'active': active,
        'stockCount': stockCount,
        'isReady': isReady,
      };
  ShopProduct copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    double? listPrice,
    double? discount,
    String? imageUrl,
    List<String>? imageUrls,
    String? imageAsset,
    String? category,
    double? rating,
    int? reviewCount,
    bool? freeDelivery,
    bool? active,
    int? stockCount,
    bool? isReady,
  }) {
    return ShopProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      listPrice: listPrice ?? this.listPrice,
      discount: discount ?? this.discount,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      imageAsset: imageAsset ?? this.imageAsset,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      freeDelivery: freeDelivery ?? this.freeDelivery,
      active: active ?? this.active,
      stockCount: stockCount ?? this.stockCount,
      isReady: isReady ?? this.isReady,
    );
  }
}

class CartItem {
  final ShopProduct product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  double get unitPrice => product.salePrice;
  double get lineTotal => unitPrice * quantity;
}

class ShopCartService extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();
  int get itemCount =>
      _items.values.fold(0, (sum, item) => sum + item.quantity);
  double get total =>
      _items.values.fold(0.0, (sum, item) => sum + item.lineTotal);
  bool get isEmpty => _items.isEmpty;

  void add(ShopProduct product, {int qty = 1}) {
    if (!product.isReady) return;
    if (product.stockCount <= 0) return;
    final existing = _items[product.id];
    if (existing != null) {
      existing.quantity += qty;
    } else {
      _items[product.id] = CartItem(product: product, quantity: qty);
    }
    notifyListeners();
  }

  void setQuantity(String productId, int qty) {
    if (!_items.containsKey(productId)) return;
    if (qty <= 0) {
      _items.remove(productId);
    } else {
      _items[productId]!.quantity = qty;
    }
    notifyListeners();
  }

  void remove(String productId) {
    _items.remove(productId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

/// Live Firestore catalog for `shop_products`.
class ShopCatalogService extends ChangeNotifier {
  final List<ShopProduct> _rawProducts = [];
  /// Live averages from each product's `reviews` subcollection.
  final Map<String, ({double rating, int count})> _reviewAgg = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _reviewSubs = [];
  bool isLoading = true;
  bool _reviewsReady = false;
  String? error;

  List<ShopProduct> get products =>
      List.unmodifiable(_rawProducts.map(_withLiveRating));
  List<ShopProduct> get activeProducts =>
      products.where((p) => p.active).toList(growable: false);

  ShopProduct _withLiveRating(ShopProduct p) {
    if (!_reviewsReady) {
      return p.copyWith(rating: 0, reviewCount: 0);
    }
    final agg = _reviewAgg[p.id];
    if (agg == null) return p.copyWith(rating: 0, reviewCount: 0);
    return p.copyWith(rating: agg.rating, reviewCount: agg.count);
  }

  ShopCatalogService() {
    bind();
  }

  void bind() {
    _sub?.cancel();
    _cancelReviewSubs();
    isLoading = true;
    _reviewsReady = false;
    error = null;
    notifyListeners();

    _sub = FirebaseFirestore.instance
        .collection(collectionShopProducts)
        .snapshots()
        .listen(
      (snap) {
        final list = snap.docs
            .map((d) => ShopProduct.fromMap(d.data(), d.id))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _rawProducts
          ..clear()
          ..addAll(list);
        isLoading = false;
        error = null;
        _bindProductReviews();
        notifyListeners();
      },
      onError: (e) {
        error = '$e';
        isLoading = false;
        printDebugMsg('ShopCatalogService: $e');
        notifyListeners();
      },
    );
  }

  void _cancelReviewSubs() {
    for (final s in _reviewSubs) {
      s.cancel();
    }
    _reviewSubs.clear();
  }

  void _bindProductReviews() {
    _cancelReviewSubs();
    _reviewAgg.clear();

    if (_rawProducts.isEmpty) {
      _reviewsReady = true;
      notifyListeners();
      return;
    }

    for (final product in List<ShopProduct>.from(_rawProducts)) {
      final sub = FirebaseFirestore.instance
          .collection(collectionShopProducts)
          .doc(product.id)
          .collection(collectionShopReviews)
          .snapshots()
          .listen(
        (snap) {
          if (snap.docs.isEmpty) {
            _reviewAgg.remove(product.id);
          } else {
            var sum = 0.0;
            for (final d in snap.docs) {
              final r = d.data()['rating'];
              sum += (r is num) ? r.toDouble() : 0;
            }
            _reviewAgg[product.id] = (
              rating:
                  double.parse((sum / snap.docs.length).toStringAsFixed(1)),
              count: snap.docs.length,
            );
          }
          _reviewsReady = true;
          notifyListeners();
        },
        onError: (e) {
          printDebugMsg('Shop reviews ${product.id}: $e');
          _reviewsReady = true;
          notifyListeners();
        },
      );
      _reviewSubs.add(sub);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cancelReviewSubs();
    super.dispose();
  }
}

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  State<ShopPage> createState() => _ShopPageState();
}
class _ShopPageState extends State<ShopPage> {
  final _money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
  final _searchController = TextEditingController();
  String _category = 'All';
  String _query = '';
  String _sort = 'Featured';
  bool _checkingOut = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ShopProduct> _filterAndSort(List<ShopProduct> products) {
    var list = products.where((p) {
      final inCat = _category == 'All' || p.category == _category;
      if (!inCat) return false;
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case 'Price: Low to High':
        list.sort((a, b) => a.salePrice.compareTo(b.salePrice));
      case 'Price: High to Low':
        list.sort((a, b) => b.salePrice.compareTo(a.salePrice));
      case 'Top Rated':
        list.sort((a, b) => b.rating.compareTo(a.rating));
      default:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  Future<void> _checkout(ShopCartService cart) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      MyGlobalMessage.show(
        'Login required',
        'Please log in to place an order.',
        MyMessageType.warning,
      );
      return;
    }
    if (cart.isEmpty) return;

    setState(() => _checkingOut = true);
    try {
      final orderRef = FirebaseFirestore.instance
          .collection(collectionUsers)
          .doc(user.uid)
          .collection(collectionShopOrders)
          .doc();

      final items = cart.items
          .map((i) => {
                'productId': i.product.id,
                'name': i.product.name,
                'catalogPrice': i.product.price,
                'price': i.unitPrice,
                'discount': i.product.discount,
                'quantity': i.quantity,
                'lineTotal': i.lineTotal,
              })
          .toList();

      await orderRef.set({
        'orderId': orderRef.id,
        'userId': user.uid,
        'email': user.email,
        'items': items,
        'total': cart.total,
        'currency': 'ZAR',
        'status': 'pending_payment',
        'paymentProvider': 'payfast',
        'createdAt': FieldValue.serverTimestamp(),
      });

      final orderTotal = cart.total;
      final orderId = orderRef.id;
      cart.clear();
      if (!mounted) return;

      Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: colorAppTitle,
          title: const MyText(text: 'Order placed', color: Colors.white),
          content: MyText(
            text:
                'Order $orderId was saved.\n\nTotal: ${_money.format(orderTotal)}\n\nPayFast card checkout can be connected next using your merchant account.',
            color: Colors.grey,
            fontsize: 15,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const MyText(text: 'OK', color: colorOrange),
            ),
          ],
        ),
      );
    } catch (e) {
      MyGlobalSnackBar.show('Checkout failed: $e');
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorAppBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer<ShopCartService>(
          builder: (_, liveCart, __) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              builder: (_, controller) {
                return Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Shopping Basket',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!liveCart.isEmpty)
                            TextButton(
                              onPressed: liveCart.clear,
                              child: const Text(
                                'Remove all',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorTileLight.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        liveCart.isEmpty
                            ? 'Your basket is empty'
                            : '${liveCart.itemCount} item${liveCart.itemCount == 1 ? '' : 's'} · ${_money.format(liveCart.total)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: liveCart.isEmpty
                          ? const Center(
                              child: Text(
                                'Add items from the shop to get started',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          : ListView.separated(
                              controller: controller,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              itemCount: liveCart.items.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(color: Colors.white12),
                              itemBuilder: (_, i) {
                                final item = liveCart.items[i];
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: (item.product.primaryImageUrl !=
                                                    null &&
                                                item.product.primaryImageUrl!
                                                    .trim()
                                                    .isNotEmpty)
                                            ? Colors.white
                                                .withValues(alpha: 0.92)
                                            : colorAppBar,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: _ProductThumb(
                                        product: item.product,
                                        size: 56,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.product.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _money.format(item.unitPrice),
                                            style: const TextStyle(
                                              color: colorOrange,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () =>
                                                    liveCart.setQuantity(
                                                  item.product.id,
                                                  item.quantity - 1,
                                                ),
                                                icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              Text(
                                                '${item.quantity}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () =>
                                                    liveCart.setQuantity(
                                                  item.product.id,
                                                  item.quantity + 1,
                                                ),
                                                icon: const Icon(
                                                  Icons.add_circle_outline,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              const Spacer(),
                                              TextButton(
                                                onPressed: () => liveCart
                                                    .remove(item.product.id),
                                                child: const Text(
                                                  'Remove',
                                                  style: TextStyle(
                                                    color: Colors.redAccent,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    if (!liveCart.isEmpty)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        decoration: BoxDecoration(
                          color: colorAppTitle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'To pay',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _money.format(liveCart.total),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorOrange,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  onPressed: _checkingOut
                                      ? null
                                      : () => _checkout(liveCart),
                                  child: _checkingOut
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Secure Checkout · PayFast',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(color: Colors.black87, fontSize: 14),
        cursorColor: colorAppBar,
        decoration: InputDecoration(
          hintText: 'Search for products, brands and more',
          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade700),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: Colors.grey.shade700, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      height: 118,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [
            colorAppBar,
            colorTileLight,
            colorAppBar.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white12),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -30,
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 140,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorOrange,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'DEALS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Limitless IoT Shop',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Hardware, kits & support',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<ShopCartService>();
    final catalog = context.watch<ShopCatalogService>();

    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _buildSearchBar(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  tooltip: 'Basket',
                  onPressed: _openCart,
                  icon: const Icon(Icons.shopping_cart_outlined),
                ),
                if (cart.itemCount > 0)
                  Positioned(
                    right: 6,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: colorOrange,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        '${cart.itemCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: _buildCatalogBody(cart, catalog),
    );
  }

  Widget _buildCatalogBody(ShopCartService cart, ShopCatalogService catalog) {
    if (catalog.isLoading) {
      return Center(child: myProgressCircle());
    }
    if (catalog.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white38, size: 40),
              const SizedBox(height: 12),
              const Text(
                'Could not load shop from Firestore',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                catalog.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: catalog.bind,
                child: const Text('Retry', style: TextStyle(color: colorOrange)),
              ),
            ],
          ),
        ),
      );
    }

    final products = catalog.activeProducts;
    if (products.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No products in the shop yet.\nAdd items in Setup Shop.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
        ),
      );
    }

    final categories = <String>{
      'All',
      ...products.map((p) => p.category),
    }.toList();
    final filtered = _filterAndSort(products);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildPromoBanner()),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = categories[i];
                final selected = cat == _category;
                return FilterChip(
                  label: Text(cat),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _category = cat),
                  selectedColor: colorOrange,
                  backgroundColor: colorAppBar,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: selected ? colorOrange : Colors.white24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  initialValue: _sort,
                  color: colorAppBar,
                  onSelected: (v) => setState(() => _sort = v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'Featured',
                      child: Text('Featured', style: TextStyle(color: Colors.white)),
                    ),
                    PopupMenuItem(
                      value: 'Price: Low to High',
                      child: Text('Price: Low to High', style: TextStyle(color: Colors.white)),
                    ),
                    PopupMenuItem(
                      value: 'Price: High to Low',
                      child: Text('Price: High to Low', style: TextStyle(color: Colors.white)),
                    ),
                    PopupMenuItem(
                      value: 'Top Rated',
                      child: Text('Top Rated', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorAppBar,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Text(_sort, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No products found', style: TextStyle(color: Colors.grey))),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.52,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final product = filtered[i];
                  return _ProductCard(
                    product: product,
                    priceLabel: _money.format(product.salePrice),
                    listPriceLabel: product.hasDeal
                        ? _money.format(product.price)
                        : null,
                    onOpen: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ShopProductDetailPage(product: product),
                        ),
                      );
                    },
                    onAdd: () {
                      if (!product.isReady) {
                        MyGlobalSnackBar.show(
                          '${product.name} is coming soon',
                        );
                        return;
                      }
                      if (product.stockCount <= 0) {
                        MyGlobalSnackBar.show(
                          '${product.name} is out of stock',
                        );
                        return;
                      }
                      cart.add(product);
                      MyGlobalSnackBar.show('${product.name} added to basket');
                    },
                  );
                },
                childCount: filtered.length,
              ),
            ),
          ),
      ],
    );
  }
}
class _ProductCard extends StatelessWidget {
  final ShopProduct product;
  final String priceLabel;
  final String? listPriceLabel;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  const _ProductCard({
    required this.product,
    required this.priceLabel,
    required this.listPriceLabel,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorAppBar,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image plate — flex share so details always keep room for the button.
              Expanded(
                flex: 5,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: (product.primaryImageUrl != null &&
                                product.primaryImageUrl!.trim().isNotEmpty)
                            ? Colors.white.withValues(alpha: 0.94)
                            : colorAppBar,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: _ProductThumb(product: product, size: 96),
                        ),
                      ),
                    ),
                    if (!product.isReady)
                      Positioned(
                        left: -38,
                        top: 14,
                        child: Transform.rotate(
                          angle: -math.pi / 4,
                          child: Container(
                            width: 130,
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorDrawer,
                                  colorDrawer.withValues(alpha: 0.85),
                                  const Color(0xFF1E3A8A),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: const Text(
                              'COMING SOON',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (product.hasDeal)
                      Positioned(
                        left: -34,
                        top: 12,
                        child: Transform.rotate(
                          angle: -math.pi / 4,
                          child: Container(
                            width: 110,
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorOrange,
                                  colorOrange.withValues(alpha: 0.9),
                                  const Color(0xFFE11D48),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              '-${product.savePercent}%',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                ...List.generate(5, (i) {
                                  final threshold = i + 1.0;
                                  final IconData icon;
                                  if (product.rating >= threshold) {
                                    icon = Icons.star;
                                  } else if (product.rating >=
                                      threshold - 0.5) {
                                    icon = Icons.star_half;
                                  } else {
                                    icon = Icons.star_border;
                                  }
                                  return Icon(icon,
                                      size: 12, color: colorOrange);
                                }),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    product.reviewCount > 0
                                        ? '${product.rating.toStringAsFixed(1)} (${product.reviewCount})'
                                        : 'No reviews',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              priceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (listPriceLabel != null)
                              Text(
                                listPriceLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 11,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.white38,
                                ),
                              ),
                            if (product.freeDelivery)
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  'FREE DELIVERY',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFF4ADE80),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 32,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: product.isReady
                                ? colorOrange
                                : Colors.white24,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          onPressed: product.isReady &&
                                  product.stockCount > 0
                              ? onAdd
                              : null,
                          child: Text(
                            !product.isReady
                                ? 'Coming Soon'
                                : product.stockCount <= 0
                                    ? 'Out of Stock'
                                    : 'Add to Cart',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
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
class _ProductThumb extends StatelessWidget {
  final ShopProduct product;
  final double size;

  const _ProductThumb({required this.product, required this.size});

  String get _placeholder => iconShopNoImage;

  @override
  Widget build(BuildContext context) {
    final url = product.primaryImageUrl;
    if (url != null && url.trim().isNotEmpty) {
      return Center(
        child: NetworkAvatar(
          imageUrl: url,
          size: size,
          fit: BoxFit.contain,
          fallbackAsset: _placeholder,
        ),
      );
    }

    return Center(
      child: Image.asset(
        _placeholder,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
