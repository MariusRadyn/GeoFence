import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/shop_product_image.dart';
import 'package:geofence/shop_checkout_page.dart';
import 'package:geofence/shop_product_detail_page.dart';
import 'package:geofence/shop_subscription_page.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

const String collectionShopProducts = 'shop_products';
const String collectionShopOrders = 'shop_orders';
const String collectionShopReviews = 'reviews';
const String collectionShopReturns = 'returns';
const String collectionShopCancellations = 'cancellations';

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
  /// Optional monthly subscription amount in ZAR (0 = none).
  final double subscriptionMonthly;
  final double weightKg;
  final double lengthCm;
  final double widthCm;
  final double heightCm;

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
    this.subscriptionMonthly = 0,
    this.weightKg = 1,
    this.lengthCm = 20,
    this.widthCm = 15,
    this.heightCm = 10,
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
      subscriptionMonthly: asDouble(map['subscriptionMonthly']),
      weightKg: asDouble(map['weightKg'], 1),
      lengthCm: asDouble(map['lengthCm'], 20),
      widthCm: asDouble(map['widthCm'], 15),
      heightCm: asDouble(map['heightCm'], 10),
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
        'subscriptionMonthly': subscriptionMonthly,
        'weightKg': weightKg,
        'lengthCm': lengthCm,
        'widthCm': widthCm,
        'heightCm': heightCm,
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
    double? subscriptionMonthly,
    double? weightKg,
    double? lengthCm,
    double? widthCm,
    double? heightCm,
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
      subscriptionMonthly:
          subscriptionMonthly ?? this.subscriptionMonthly,
      weightKg: weightKg ?? this.weightKg,
      lengthCm: lengthCm ?? this.lengthCm,
      widthCm: widthCm ?? this.widthCm,
      heightCm: heightCm ?? this.heightCm,
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

  /// Flat shipping applies only when at least one item is not free delivery.
  bool get needsShipping =>
      _items.values.any((item) => !item.product.freeDelivery);

  bool get hasSubscription =>
      _items.values.any((item) => item.product.subscriptionMonthly > 0);

  double get subscriptionMonthlyTotal => _items.values.fold(
        0.0,
        (sum, item) =>
            sum + (item.product.subscriptionMonthly * item.quantity),
      );

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

  /// Opens Online Shop in this app instance (used after payment return).
  static void openInApp() {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ShopPage()),
      (route) => route.isFirst,
    );
  }
}
class _ShopPageState extends State<ShopPage> {
  final _money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
  final _searchController = TextEditingController();
  String _category = 'All';
  String _query = '';
  String _sort = 'Featured';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _shopGridCrossAxisCount(BuildContext context) {
    if (!kIsWeb) return 2;
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1400) return 8;
    if (width >= 1200) return 6;
    if (width >= 900) return 5;
    if (width >= 700) return 4;
    if (width >= 500) return 3;
    return 2;
  }

  double _shopGridChildAspectRatio(BuildContext context) {
    // Lower ratio = taller tiles (square image + text/button below).
    if (!kIsWeb) return 0.52;
    switch (_shopGridCrossAxisCount(context)) {
      case 8:
        return 0.58;
      case 6:
        return 0.62;
      case 5:
        return 0.64;
      case 4:
        return 0.66;
      case 3:
        return 0.66;
      default:
        return 0.62;
    }
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
    Navigator.of(context).pop();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => cart.hasSubscription
            ? const ShopSubscriptionPage()
            : const ShopCheckoutPage(),
      ),
    );
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
                            : liveCart.hasSubscription
                                ? '${liveCart.itemCount} item${liveCart.itemCount == 1 ? '' : 's'} · ${_money.format(liveCart.total)} · ${_money.format(liveCart.subscriptionMonthlyTotal)}/mo'
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
                          : ListView(
                              controller: controller,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              children: [
                                for (final item in liveCart.items) ...[
                                  _basketProductRow(liveCart, item),
                                  if (item.product.subscriptionMonthly > 0) ...[
                                    const SizedBox(height: 8),
                                    _basketSubscriptionRow(item),
                                  ],
                                  const Divider(
                                    color: Colors.white12,
                                    height: 20,
                                  ),
                                ],
                              ],
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
                                    'To pay today',
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
                              if (liveCart.hasSubscription) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Text(
                                      'Subscription',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${_money.format(liveCart.subscriptionMonthlyTotal)}/mo',
                                      style: const TextStyle(
                                        color: colorOrange,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                                  onPressed: () => _checkout(liveCart),
                                  child: const Text(
                                    'Secure Checkout',
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

  Widget _basketProductRow(ShopCartService cart, CartItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 72,
            height: 72,
            child: ColoredBox(
              color: (item.product.primaryImageUrl != null &&
                      item.product.primaryImageUrl!.trim().isNotEmpty)
                  ? Colors.white.withValues(alpha: 0.92)
                  : colorAppBar,
              child: ShopProductImage(
                imageUrl: item.product.primaryImageUrl,
                side: 72,
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
                    visualDensity: VisualDensity.compact,
                    onPressed: () => cart.setQuantity(
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
                    style: const TextStyle(color: Colors.white),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => cart.setQuantity(
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
                    onPressed: () => cart.remove(item.product.id),
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
  }

  Widget _basketSubscriptionRow(CartItem item) {
    final monthly = item.product.subscriptionMonthly * item.quantity;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorOrange.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorOrange,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.autorenew,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subscription',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.quantity > 1
                      ? '${item.product.name} · ${item.quantity} × ${_money.format(item.product.subscriptionMonthly)}/mo'
                      : '${item.product.name} · monthly',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${_money.format(monthly)}/mo',
            style: const TextStyle(
              color: colorOrange,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
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

  Widget _buildNeonShoppingBagIcon({double size = 140}) {
    const neonBlue = Color(0xFF00E5FF);
    const neonCore = Color(0xFF8BE5F5);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Icon(
            Icons.shopping_bag_outlined,
            size: size,
            color: neonBlue.withValues(alpha: 0.55),
          ),
        ),
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Icon(
            Icons.shopping_bag_outlined,
            size: size,
            color: neonBlue.withValues(alpha: 0.85),
          ),
        ),
        Icon(
          Icons.shopping_bag_outlined,
          size: size,
          color: neonCore,
        ),
      ],
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
            child: _buildNeonShoppingBagIcon(),
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
                    child: IgnorePointer(
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
      // Keep off-screen tile cache small — helps iOS Safari memory.
      // ignore: deprecated_member_use
      cacheExtent: kIsWeb ? 180 : 250,
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
            padding: EdgeInsets.fromLTRB(
              kIsWeb ? 12 : 10,
              4,
              kIsWeb ? 12 : 10,
              24,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _shopGridCrossAxisCount(context),
                mainAxisSpacing: kIsWeb ? 8 : 10,
                crossAxisSpacing: kIsWeb ? 8 : 10,
                childAspectRatio: _shopGridChildAspectRatio(context),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final product = filtered[i];
                  return RepaintBoundary(
                    child: _ProductCard(
                      product: product,
                      compact: kIsWeb ||
                          MediaQuery.sizeOf(context).width < 480,
                      priceLabel: _money.format(product.salePrice),
                      listPriceLabel: product.hasDeal
                          ? _money.format(product.price)
                          : null,
                      subscriptionLabel: product.subscriptionMonthly > 0
                          ? _money.format(product.subscriptionMonthly)
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
                    ),
                  );
                },
                childCount: filtered.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
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
  final String? subscriptionLabel;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final bool compact;

  const _ProductCard({
    required this.product,
    required this.priceLabel,
    required this.listPriceLabel,
    required this.subscriptionLabel,
    required this.onOpen,
    required this.onAdd,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final nameSize = compact ? 10.0 : 12.0;
    final priceSize = compact ? 12.0 : 15.0;
    final listPriceSize = compact ? 9.0 : 11.0;
    final starSize = compact ? 10.0 : 12.0;
    final reviewSize = compact ? 8.0 : 10.0;
    final buttonHeight = compact ? 26.0 : 32.0;
    final buttonFontSize = compact ? 9.0 : 11.0;
    final bodyPadding = compact
        ? const EdgeInsets.fromLTRB(6, 4, 6, 4)
        : const EdgeInsets.fromLTRB(8, 5, 8, 6);

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
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  // Keep image area strictly square; crop overflow.
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: (product.primaryImageUrl != null &&
                                product.primaryImageUrl!.trim().isNotEmpty)
                            ? Colors.white.withValues(alpha: 0.94)
                            : colorAppBar,
                        child: const SizedBox.expand(),
                      ),
                      Positioned.fill(
                        child: ShopProductImage(
                          imageUrl: product.primaryImageUrl,
                        ),
                      ),
                      if (subscriptionLabel != null)
                        Positioned(
                          right: compact ? 5 : 8,
                          top: compact ? 5 : 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 8 : 11,
                              vertical: compact ? 4 : 6,
                            ),
                            decoration: BoxDecoration(
                              color: colorOrange,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              'Subscribe',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 10 : 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      if (!product.isReady)
                        Positioned(
                          left: compact ? -46 : -38,
                          top: compact ? 30 : 26,
                          child: Transform.rotate(
                            angle: -math.pi / 4,
                            child: Container(
                              width: compact ? 140 : 140,
                              padding: EdgeInsets.symmetric(
                                  vertical: compact ? 3 : 5),
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
                              child: Text(
                                'COMING SOON',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 7 : 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        )
                      else if (product.hasDeal)
                        Positioned(
                          left: compact ? -25 : -34,
                          top: compact ? 18 : 10,
                          child: Transform.rotate(
                            angle: -math.pi / 4,
                            child: Container(
                              width: compact ? 100 : 110,
                              padding: EdgeInsets.symmetric(
                                  vertical: compact ? 3 : 5),
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
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 9 : 11,
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
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: bodyPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                product.name,
                                maxLines: compact ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: nameSize,
                                  fontWeight: FontWeight.w600,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 1 : 2),
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
                                      size: starSize, color: colorOrange);
                                }),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    product.reviewCount > 0
                                        ? '${product.rating.toStringAsFixed(1)} (${product.reviewCount})'
                                        : 'No reviews',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: reviewSize,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? 1 : 3),
                            Text(
                              priceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: priceSize,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            if (listPriceLabel != null)
                              Text(
                                listPriceLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: listPriceSize,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.white38,
                                  height: 1.1,
                                ),
                              ),
                            if (subscriptionLabel != null)
                              Padding(
                                padding: EdgeInsets.only(top: compact ? 1 : 2),
                                child: Text(
                                  '+ $subscriptionLabel / month',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colorIceBlue,
                                    fontSize: compact ? 8 : 10,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            if (product.freeDelivery && !compact)
                              Padding(
                                padding: EdgeInsets.only(top: compact ? 1 : 2),
                                child: Text(
                                  'FREE DELIVERY',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: const Color(0xFF4ADE80),
                                    fontSize: compact ? 7 : 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 3 : 4),
                      SizedBox(
                        width: double.infinity,
                        height: buttonHeight,
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
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: buttonFontSize,
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
