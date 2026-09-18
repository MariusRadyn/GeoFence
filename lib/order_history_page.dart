import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:geofence/bob_go_csv.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final _money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
  final _dateFormat = DateFormat('dd MMM yyyy, HH:mm');

  String? get _uid => currentDataOwnerUid();

  CollectionReference<Map<String, dynamic>>? get _ordersRef {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid)
        .collection(collectionShopOrders);
  }

  String _formatOrderDate(dynamic value) {
    if (value is Timestamp) {
      return _dateFormat.format(value.toDate());
    }
    return 'Date unavailable';
  }

  String _orderStatusLabel(String? status) {
    return switch (status) {
      'pending_payment' => 'Pending payment',
      'paid' => 'Paid',
      'shipped' => 'Shipped',
      'delivered' => 'Delivered',
      'cancelled' => 'Cancelled',
      _ => status ?? 'Unknown',
    };
  }

  Color _orderStatusColor(String? status) {
    return switch (status) {
      'pending_payment' => Colors.orangeAccent,
      'paid' => colorIceBlue,
      'shipped' => Colors.lightBlueAccent,
      'delivered' => Colors.greenAccent,
      'cancelled' => Colors.redAccent,
      _ => Colors.white54,
    };
  }

  Color _returnStatusColor(String? status) {
    return switch (status) {
      'requested' => Colors.orangeAccent,
      'approved' => Colors.greenAccent,
      'rejected' => Colors.redAccent,
      'completed' => Colors.white54,
      _ => Colors.white38,
    };
  }

  String _returnStatusLabel(String? status) {
    return switch (status) {
      'requested' => 'Return requested',
      'approved' => 'Return approved',
      'rejected' => 'Return rejected',
      'completed' => 'Return completed',
      'cancelled' => 'Return cancelled',
      _ => '',
    };
  }

  bool _orderHasReturnRequested(
    Map<String, List<Map<String, dynamic>>> returnsByProduct,
  ) {
    for (final returns in returnsByProduct.values) {
      if (returns.any((r) => r['status']?.toString() == 'requested')) {
        return true;
      }
    }
    return false;
  }

  Widget _buildStatusTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: MyText(
        text: label,
        color: color,
        fontsize: 11,
      ),
    );
  }

  Future<(List<Map<String, dynamic>>, Map<String, List<Map<String, dynamic>>>)>
      _loadOrderDetails(
    String orderId,
    List<Map<String, dynamic>> items,
  ) async {
    final results = await Future.wait([
      _enrichOrderItems(items),
      _loadReturnsForOrder(orderId),
      _loadCancellationsForOrder(orderId),
    ]);
    final enriched = results[0] as List<Map<String, dynamic>>;
    final cancellations = results[2] as List<Map<String, dynamic>>;
    return (
      _buildDisplayItems(enriched, cancellations),
      results[1] as Map<String, List<Map<String, dynamic>>>,
    );
  }

  Future<List<Map<String, dynamic>>> _loadCancellationsForOrder(
    String orderId,
  ) async {
    final uid = _uid;
    if (uid == null) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid)
        .collection(collectionShopOrders)
        .doc(orderId)
        .collection(collectionShopCancellations)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => {
              ...doc.data(),
              'cancellationId': doc.id,
            })
        .toList();
  }

  int _itemActiveQuantity(Map<String, dynamic> item) {
    return _asInt(item['quantity'], 0);
  }

  int _itemCancelledQuantity(Map<String, dynamic> item) {
    return _asInt(item['cancelledQuantity'], 0);
  }

  int _itemOrderedQuantity(Map<String, dynamic> item) {
    final ordered = _asInt(item['orderedQuantity'], 0);
    if (ordered > 0) return ordered;
    return _itemActiveQuantity(item) + _itemCancelledQuantity(item);
  }

  bool _isItemFullyCancelled(Map<String, dynamic> item) {
    if (item['isCancelledHistoryTile'] == true) return true;
    if (item['itemStatus']?.toString() == 'cancelled') return true;
    return _itemActiveQuantity(item) <= 0 && _itemCancelledQuantity(item) > 0;
  }

  Map<String, dynamic> _cancelledHistoryTile(
    Map<String, dynamic> item,
    int cancelledQty,
  ) {
    final activeQty = _itemActiveQuantity(item);
    final unitPrice = _asDouble(item['price']) > 0
        ? _asDouble(item['price'])
        : (_asInt(item['orderedQuantity'], activeQty + cancelledQty) > 0
            ? _asDouble(item['lineTotal']) /
                _itemActiveQuantity(item).clamp(1, 999999)
            : 0);

    return {
      ...item,
      'quantity': 0,
      'cancelledQuantity': cancelledQty,
      'orderedQuantity': cancelledQty,
      'lineTotal': 0,
      'itemStatus': 'cancelled',
      'isCancelledHistoryTile': true,
      'price': unitPrice > 0 ? unitPrice : item['price'],
    };
  }

  List<Map<String, dynamic>> _buildDisplayItems(
    List<Map<String, dynamic>> orderItems,
    List<Map<String, dynamic>> cancellations,
  ) {
    final expanded = <Map<String, dynamic>>[];

    for (final source in orderItems) {
      final item = Map<String, dynamic>.from(source);
      if (item['orderedQuantity'] == null) {
        item['orderedQuantity'] = _itemOrderedQuantity(item);
      }

      final activeQty = _itemActiveQuantity(item);
      final cancelledQty = _itemCancelledQuantity(item);

      if (cancelledQty > 0 && activeQty > 0) {
        expanded.add(_cancelledHistoryTile(item, cancelledQty));

        final activeItem = Map<String, dynamic>.from(item);
        activeItem['cancelledQuantity'] = 0;
        activeItem.remove('itemStatus');
        activeItem.remove('isCancelledHistoryTile');
        expanded.add(activeItem);
      } else {
        expanded.add(item);
      }
    }

    final productIds =
        expanded.map((item) => item['productId']?.toString()).toSet();

    final legacyCancelled = <String, Map<String, dynamic>>{};
    for (final cancellation in cancellations) {
      final productId = cancellation['productId']?.toString() ?? '';
      if (productId.isEmpty || productIds.contains(productId)) continue;

      final existing = legacyCancelled[productId];
      if (existing == null) {
        legacyCancelled[productId] = {
          'productId': productId,
          'name': cancellation['productName']?.toString() ?? 'Product',
          'price': cancellation['price'] ?? 0,
          'quantity': 0,
          'orderedQuantity': _asInt(cancellation['quantity'], 1),
          'cancelledQuantity': _asInt(cancellation['quantity'], 1),
          'lineTotal': 0,
          'itemStatus': 'cancelled',
          'isCancelledHistoryTile': true,
        };
      } else {
        final addQty = _asInt(cancellation['quantity'], 1);
        existing['orderedQuantity'] =
            _asInt(existing['orderedQuantity'], 0) + addQty;
        existing['cancelledQuantity'] =
            _asInt(existing['cancelledQuantity'], 0) + addQty;
      }
    }

    expanded.addAll(legacyCancelled.values);
    return expanded;
  }

  int _activeReturnQuantity(List<Map<String, dynamic>> returns) {
    return returns
        .where(
          (r) => ['requested', 'approved'].contains(r['status']?.toString()),
        )
        .fold(0, (total, r) => total + _asInt(r['quantity'], 1));
  }

  Map<String, dynamic>? _latestActiveReturn(List<Map<String, dynamic>> returns) {
    for (final item in returns) {
      final status = item['status']?.toString();
      if (status == 'requested' || status == 'approved') {
        return item;
      }
    }
    return null;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadReturnsForOrder(
    String orderId,
  ) async {
    final uid = _uid;
    if (uid == null) return {};

    final snapshot = await FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid)
        .collection(collectionShopOrders)
        .doc(orderId)
        .collection(collectionShopReturns)
        .orderBy('createdAt', descending: true)
        .get();

    final returnsByProduct = <String, List<Map<String, dynamic>>>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final productId = data['productId']?.toString() ?? doc.id;
      returnsByProduct.putIfAbsent(productId, () => []).add({
        ...data,
        'returnId': doc.id,
      });
    }
    return returnsByProduct;
  }

  Future<bool> _submitReturn({
    required String orderId,
    required Map<String, dynamic> item,
    required String description,
    required int returnQuantity,
  }) async {
    final uid = _uid;
    if (uid == null) {
      MyGlobalMessage.show(
        'Login required',
        'Please log in to request a return.',
        MyMessageType.warning,
      );
      return false;
    }

    final trimmed = description.trim();
    if (trimmed.isEmpty) {
      MyGlobalMessage.show(
        'Return reason',
        'Please describe why you want to return this product.',
        MyMessageType.info,
      );
      return false;
    }

    final productId = item['productId']?.toString() ?? '';
    if (productId.isEmpty) {
      MyGlobalMessage.show(
        'Return failed',
        'This order item is missing a product id.',
        MyMessageType.error,
      );
      return false;
    }

    final orderedQuantity = _itemActiveQuantity(item);
    if (orderedQuantity < 1) {
      MyGlobalMessage.show(
        'Return unavailable',
        'This item has no active quantity left to return.',
        MyMessageType.info,
      );
      return false;
    }
    if (returnQuantity < 1 || returnQuantity > orderedQuantity) {
      MyGlobalMessage.show(
        'Return quantity',
        'Please choose a quantity between 1 and $orderedQuantity.',
        MyMessageType.info,
      );
      return false;
    }

    final returnsRef = FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid)
        .collection(collectionShopOrders)
        .doc(orderId)
        .collection(collectionShopReturns);

    final existing = await returnsRef
        .where('productId', isEqualTo: productId)
        .get();

    final activeReturnQty = existing.docs
        .where(
          (doc) => ['requested', 'approved']
              .contains(doc.data()['status']?.toString()),
        )
        .fold<int>(
          0,
          (total, doc) => total + _asInt(doc.data()['quantity'], 1),
        );
    final remainingQty = orderedQuantity - activeReturnQty;

    if (returnQuantity > remainingQty) {
      MyGlobalMessage.show(
        'Return quantity',
        remainingQty <= 0
            ? 'All units for this product already have an active return request.'
            : 'You can return up to $remainingQty more unit${remainingQty == 1 ? '' : 's'}.',
        MyMessageType.warning,
      );
      return false;
    }

    final unitPrice = _asDouble(item['price']) > 0
        ? _asDouble(item['price'])
        : (orderedQuantity > 0
            ? _asDouble(item['lineTotal']) / orderedQuantity
            : 0);
    final returnLineTotal = unitPrice * returnQuantity;

    final returnRef = returnsRef.doc();
    await returnRef.set({
      'returnId': returnRef.id,
      'orderId': orderId,
      'userId': uid,
      'productId': productId,
      'productName': item['name']?.toString() ?? 'Product',
      'orderedQuantity': orderedQuantity,
      'quantity': returnQuantity,
      'price': unitPrice,
      'lineTotal': returnLineTotal,
      'description': trimmed,
      'status': 'requested',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return true;
  }

  void _showReturnSubmittedMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MyGlobalMessage.show(
        'Return',
        'Request submitted, we will contact you',
        MyMessageType.info,
      );
    });
  }

  Map<String, dynamic>? _pendingReturn(
    List<Map<String, dynamic>> returns,
  ) {
    for (final item in returns) {
      if (item['status']?.toString() == 'requested') {
        return item;
      }
    }
    return null;
  }

  Future<bool> _cancelReturnRequest({
    required String orderId,
    required String returnId,
  }) async {
    final uid = _uid;
    if (uid == null) {
      MyGlobalMessage.show(
        'Login required',
        'Please log in to cancel a return request.',
        MyMessageType.warning,
      );
      return false;
    }

    await FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid)
        .collection(collectionShopOrders)
        .doc(orderId)
        .collection(collectionShopReturns)
        .doc(returnId)
        .update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return true;
  }

  void _showReturnCancelledMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MyGlobalMessage.show(
        'Return',
        'Return request cancelled',
        MyMessageType.info,
      );
    });
  }

  bool _canCancelOrderItem(String? status) {
    return switch (status) {
      'pending_payment' => true,
      'paid' => true,
      _ => false,
    };
  }

  Future<bool> _cancelOrderItem({
    required String orderId,
    required Map<String, dynamic> item,
    required int cancelQuantity,
  }) async {
    final uid = _uid;
    if (uid == null) {
      MyGlobalMessage.show(
        'Login required',
        'Please log in to cancel an item.',
        MyMessageType.warning,
      );
      return false;
    }

    final productId = item['productId']?.toString() ?? '';
    if (productId.isEmpty) {
      MyGlobalMessage.show(
        'Cancel failed',
        'This order item is missing a product id.',
        MyMessageType.error,
      );
      return false;
    }

    if (cancelQuantity < 1) {
      MyGlobalMessage.show(
        'Cancel quantity',
        'Please choose at least 1 item to cancel.',
        MyMessageType.info,
      );
      return false;
    }

    final orderRef = FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid)
        .collection(collectionShopOrders)
        .doc(orderId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(orderRef);
        if (!snap.exists) {
          throw Exception('Order not found');
        }

        final data = snap.data()!;
        final items = (data['items'] as List<dynamic>? ?? [])
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList();

        final index = items.indexWhere(
          (line) => line['productId']?.toString() == productId,
        );
        if (index < 0) {
          throw Exception('Item not found in order');
        }

        final line = Map<String, dynamic>.from(items[index]);
        final currentQty = _asInt(line['quantity'], 1);
        if (cancelQuantity > currentQty) {
          throw Exception(
            'You can only cancel up to $currentQty for this product.',
          );
        }

        final unitPrice = _asDouble(line['price']) > 0
            ? _asDouble(line['price'])
            : (currentQty > 0
                ? _asDouble(line['lineTotal']) / currentQty
                : 0);
        final cancelLineTotal = unitPrice * cancelQuantity;
        final newQty = currentQty - cancelQuantity;
        final productName =
            line['name']?.toString() ?? item['name']?.toString() ?? 'Product';
        final orderedQty = _asInt(line['orderedQuantity'], currentQty);

        line['orderedQuantity'] = orderedQty;
        line['cancelledQuantity'] =
            _asInt(line['cancelledQuantity'], 0) + cancelQuantity;
        line['quantity'] = newQty;
        line['lineTotal'] = unitPrice * newQty;
        if (newQty <= 0) {
          line['itemStatus'] = 'cancelled';
          line['lineTotal'] = 0;
        }
        items[index] = line;

        final newTotal = items.fold<double>(
          0,
          (total, lineItem) => total + _asDouble(lineItem['lineTotal']),
        );

        final cancellationRef =
            orderRef.collection(collectionShopCancellations).doc();
        tx.set(cancellationRef, {
          'cancellationId': cancellationRef.id,
          'orderId': orderId,
          'userId': uid,
          'productId': productId,
          'productName': productName,
          'quantity': cancelQuantity,
          'price': unitPrice,
          'lineTotal': cancelLineTotal,
          'createdAt': FieldValue.serverTimestamp(),
        });

        final updates = <String, dynamic>{
          'items': items,
          'total': newTotal,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (items.every((lineItem) => _itemActiveQuantity(lineItem) <= 0)) {
          updates['status'] = 'cancelled';
          updates['cancelledAt'] = FieldValue.serverTimestamp();
        }

        tx.update(orderRef, updates);
      });
    } catch (e) {
      MyGlobalMessage.show('Cancel failed', '$e', MyMessageType.error);
      return false;
    }

    return true;
  }

  void _showItemCancelledMessage(int quantity, String productName) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MyGlobalMessage.show(
        'Order',
        quantity == 1
            ? '1 item cancelled: $productName'
            : '$quantity items cancelled: $productName',
        MyMessageType.info,
      );
    });
  }

  Future<void> _showReturnDialog({
    required String orderId,
    required Map<String, dynamic> item,
    required List<Map<String, dynamic>> existingReturns,
    required String? orderStatus,
  }) async {
    final orderedQuantity = _itemActiveQuantity(item);
    if (orderedQuantity < 1) return;

    final activeReturnQty = _activeReturnQuantity(existingReturns);
    final remainingQty = orderedQuantity - activeReturnQty;
    final pendingReturn = _pendingReturn(existingReturns);
    final latestActiveReturn = _latestActiveReturn(existingReturns);
    final viewingExisting = pendingReturn ?? latestActiveReturn;
    final isSubmittedView = pendingReturn != null;
    final isReadOnlyView = viewingExisting != null;
    final canCancelReturn = pendingReturn != null;
    final canCancelItem = !isReadOnlyView && _canCancelOrderItem(orderStatus);

    final descriptionController = TextEditingController(
      text: viewingExisting?['description']?.toString() ?? '',
    );
    var busy = false;
    var returnQuantity = viewingExisting != null
        ? _asInt(viewingExisting['quantity'], 1)
        : 1;
    final maxReturnQty = isReadOnlyView ? returnQuantity : remainingQty;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (busy || isReadOnlyView) return;
              setDialogState(() => busy = true);
              try {
                final submitted = await _submitReturn(
                  orderId: orderId,
                  item: item,
                  description: descriptionController.text,
                  returnQuantity: returnQuantity,
                );
                if (!submitted) {
                  setDialogState(() => busy = false);
                  return;
                }

                if (!ctx.mounted) return;
                Navigator.of(ctx, rootNavigator: true).pop();

                if (mounted) {
                  setState(() {});
                  _showReturnSubmittedMessage();
                }
              } catch (e) {
                setDialogState(() => busy = false);
                MyGlobalMessage.show(
                  'Return failed',
                  '$e',
                  MyMessageType.error,
                );
              }
            }

            Future<void> cancelReturn() async {
              if (busy || pendingReturn == null) return;
              final id = pendingReturn['returnId']?.toString();
              if (id == null || id.isEmpty) return;

              setDialogState(() => busy = true);
              try {
                await _cancelReturnRequest(
                  orderId: orderId,
                  returnId: id,
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx, rootNavigator: true).pop();
                if (mounted) {
                  setState(() {});
                  _showReturnCancelledMessage();
                }
              } catch (e) {
                setDialogState(() => busy = false);
                MyGlobalMessage.show(
                  'Cancel failed',
                  '$e',
                  MyMessageType.error,
                );
              }
            }

            Future<void> cancelItem() async {
              if (busy || !canCancelItem) return;

              final productName =
                  item['name']?.toString() ?? 'this product';
              final confirmed = await showDialog<bool>(
                context: ctx,
                builder: (confirmCtx) => AlertDialog(
                  backgroundColor: colorAppTitle,
                  shadowColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Colors.blue, width: 2),
                  ),
                  title: const MyText(
                    text: 'Cancel item',
                    color: Colors.white,
                  ),
                  content: MyText(
                    text:
                        'Cancel $returnQuantity of $maxReturnQty '
                        '$productName from this order?\n\n'
                        'This cannot be undone.',
                    color: Colors.grey,
                    fontsize: 16,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmCtx, false),
                      child: const MyText(text: 'No', color: Colors.white54),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(confirmCtx, true),
                      child: const MyText(
                        text: 'Yes, cancel item',
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              );

              if (confirmed != true) return;

              setDialogState(() => busy = true);
              try {
                final cancelled = await _cancelOrderItem(
                  orderId: orderId,
                  item: item,
                  cancelQuantity: returnQuantity,
                );
                if (!cancelled) {
                  setDialogState(() => busy = false);
                  return;
                }
                if (!ctx.mounted) return;
                Navigator.of(ctx, rootNavigator: true).pop();
                if (mounted) {
                  setState(() {});
                  _showItemCancelledMessage(returnQuantity, productName);
                }
              } catch (e) {
                setDialogState(() => busy = false);
                MyGlobalMessage.show(
                  'Cancel failed',
                  '$e',
                  MyMessageType.error,
                );
              }
            }

            return AlertDialog(
              backgroundColor: colorAppTitle,
              shadowColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(
                  color: Colors.blue,
                  width: 2,
                ),
              ),
              title: MyText(
                text: isSubmittedView ? 'Return request' : 'Request return',
                color: Colors.white,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _orderItemThumb(item, size: 64),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MyText(
                                text: item['name']?.toString() ?? 'Product',
                                color: Colors.white,
                                fontsize: 16,
                              ),
                              const SizedBox(height: 8),
                              MyText(
                                text:
                                    'Ordered: $orderedQuantity · ${_money.format(_asDouble(item['lineTotal']))}',
                                color: Colors.white54,
                                fontsize: 13,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (viewingExisting != null) ...[
                      const SizedBox(height: 12),
                      _buildStatusTag(
                        _returnStatusLabel(
                          viewingExisting['status']?.toString(),
                        ),
                        _returnStatusColor(
                          viewingExisting['status']?.toString(),
                        ),
                      ),
                    ],
                    if (!isReadOnlyView && activeReturnQty > 0) ...[
                      const SizedBox(height: 8),
                      MyText(
                        text:
                            '$activeReturnQty already in return · $remainingQty available',
                        color: Colors.orangeAccent,
                        fontsize: 12,
                      ),
                    ],
                    const SizedBox(height: 16),
                    MyText(
                      text: isReadOnlyView ? 'Return quantity' : 'Quantity',
                      color: Colors.white70,
                      fontsize: 14,
                    ),
                    if (!isReadOnlyView) ...[
                      const SizedBox(height: 4),
                      const MyText(
                        text: 'Used for return request or item cancellation',
                        color: Colors.white38,
                        fontsize: 11,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: busy ||
                                  isReadOnlyView ||
                                  returnQuantity <= 1
                              ? null
                              : () => setDialogState(() => returnQuantity--),
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: isReadOnlyView || returnQuantity <= 1
                                ? Colors.white24
                                : colorIceBlue,
                          ),
                        ),
                        MyText(
                          text: '$returnQuantity',
                          color: Colors.white,
                          fontsize: 18,
                        ),
                        IconButton(
                          onPressed: busy ||
                                  isReadOnlyView ||
                                  returnQuantity >= maxReturnQty
                              ? null
                              : () => setDialogState(() => returnQuantity++),
                          icon: Icon(
                            Icons.add_circle_outline,
                            color: isReadOnlyView ||
                                    returnQuantity >= maxReturnQty
                                ? Colors.white24
                                : colorIceBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        MyText(
                          text: isReadOnlyView
                              ? 'of $orderedQuantity'
                              : 'of $maxReturnQty',
                          color: Colors.white54,
                          fontsize: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const MyText(
                      text: 'Return description',
                      color: Colors.white70,
                      fontsize: 14,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 4,
                      readOnly: isReadOnlyView,
                      enabled: !busy && !isReadOnlyView,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Describe why you want to return this item',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: colorAppBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const MyText(text: 'Close', color: Colors.white54),
                ),
                if (canCancelReturn)
                  TextButton(
                    onPressed: busy ? null : cancelReturn,
                    child: MyText(
                      text: busy ? 'Cancelling...' : 'Cancel return request',
                      color: busy ? Colors.white38 : Colors.redAccent,
                    ),
                  )
                else if (!isReadOnlyView) ...[
                  if (canCancelItem)
                    TextButton(
                      onPressed: busy ? null : cancelItem,
                      child: MyText(
                        text: busy ? 'Cancelling...' : 'Cancel item',
                        color: busy ? Colors.white38 : Colors.redAccent,
                      ),
                    ),
                  TextButton(
                    onPressed: busy ? null : submit,
                    child: MyText(
                      text: busy ? 'Saving...' : 'Submit return',
                      color: busy ? Colors.white38 : colorOrange,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  bool _canExportBobGo(String? status) {
    return status == 'paid' || status == 'shipped' || status == 'delivered';
  }

  Future<void> _exportOrderCsv(String orderId, Map<String, dynamic> data) async {
    try {
      final csv = BobGoCsv.build(orders: [
        {
          ...data,
          'orderId': orderId,
        },
      ]);
      final path = await BobGoCsv.save(
        csv: csv,
        fileName: BobGoCsv.filenameFor(orderId: orderId),
      );
      if (!mounted) return;
      MyGlobalMessage.show(
        'Bob Go CSV',
        'Saved $path\nDrag it onto Bob Go → Orders → Import. Map columns the first time; later files reuse that mapping.',
        MyMessageType.info,
      );
    } catch (e) {
      MyGlobalMessage.show('Bob Go CSV', '$e', MyMessageType.error);
    }
  }

  Future<void> _exportAllShopSalesCsv() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: cloudFunctionsRegion)
          .httpsCallable('listPaidShopOrders');
      final result = await callable.call();
      final data = result.data;
      final raw = data is Map ? data['orders'] : null;
      final orders = (raw is List ? raw : const [])
          .whereType<Map>()
          .map((order) => Map<String, dynamic>.from(order))
          .toList();
      if (orders.isEmpty) {
        MyGlobalMessage.show(
          'Bob Go CSV',
          'No paid shop orders to export yet.',
          MyMessageType.warning,
        );
        return;
      }
      final csv = BobGoCsv.build(orders: orders);
      final path = await BobGoCsv.save(
        csv: csv,
        fileName: BobGoCsv.filenameFor(),
      );
      if (!mounted) return;
      MyGlobalMessage.show(
        'Bob Go CSV',
        'Saved $path (${orders.length} order${orders.length == 1 ? '' : 's'})\nDrag it onto Bob Go → Orders → Import.',
        MyMessageType.info,
      );
    } catch (e) {
      final message = e is FirebaseFunctionsException
          ? (e.message ?? e.code)
          : '$e';
      MyGlobalMessage.show('Bob Go CSV', message, MyMessageType.error);
    }
  }

  double _asDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  int _asInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  int _orderItemCount(List<Map<String, dynamic>> items) {
    return items.fold(0, (total, item) => total + _asInt(item['quantity'], 1));
  }

  String? _itemImageUrl(Map<String, dynamic> item) {
    final url = item['imageUrl']?.toString().trim();
    if (url != null && url.isNotEmpty) return url;
    return null;
  }

  String _orderItemsSummary(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return 'No items';

    final names = items
        .map((item) => item['name']?.toString().trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();

    if (names.isEmpty) return 'Basket items';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} · ${names[1]}';
    return '${names[0]} · ${names[1]} +${names.length - 2} more';
  }

  Future<List<Map<String, dynamic>>> _enrichOrderItems(
    List<Map<String, dynamic>> items,
  ) async {
    final enriched =
        items.map((item) => Map<String, dynamic>.from(item)).toList();

    final missingIds = enriched
        .where((item) => _itemImageUrl(item) == null)
        .map((item) => item['productId']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (missingIds.isEmpty) return enriched;

    final catalog = <String, Map<String, dynamic>>{};
    for (var index = 0; index < missingIds.length; index += 10) {
      final chunkEnd = (index + 10 > missingIds.length)
          ? missingIds.length
          : index + 10;
      final chunk = missingIds.sublist(index, chunkEnd);
      final snapshot = await FirebaseFirestore.instance
          .collection(collectionShopProducts)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        catalog[doc.id] = doc.data();
      }
    }

    for (final item in enriched) {
      if (_itemImageUrl(item) != null) continue;
      final productId = item['productId']?.toString();
      final product = productId != null ? catalog[productId] : null;
      if (product == null) continue;

      final imageUrls = product['imageUrls'];
      final fallbackUrl = imageUrls is List && imageUrls.isNotEmpty
          ? imageUrls.first?.toString()
          : product['imageUrl']?.toString();

      if (fallbackUrl != null && fallbackUrl.trim().isNotEmpty) {
        item['imageUrl'] = fallbackUrl.trim();
      }
      final imageAsset = product['imageAsset']?.toString();
      if (imageAsset != null && imageAsset.isNotEmpty) {
        item['imageAsset'] = imageAsset;
      }
    }

    return enriched;
  }

  Widget _orderItemThumb(Map<String, dynamic> item, {double size = 56}) {
    final imageUrl = _itemImageUrl(item);
    final imageAsset = item['imageAsset']?.toString();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: imageUrl != null
            ? Colors.white.withValues(alpha: 0.92)
            : colorAppBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(6),
      child: imageUrl != null
          ? NetworkAvatar(
              imageUrl: imageUrl,
              size: size - 12,
              fit: BoxFit.contain,
              fallbackAsset: iconShopNoImage,
            )
          : (imageAsset != null && imageAsset.isNotEmpty
              ? Image.asset(
                  imageAsset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Image.asset(
                    iconShopNoImage,
                    fit: BoxFit.contain,
                  ),
                )
              : Image.asset(
                  iconShopNoImage,
                  fit: BoxFit.contain,
                )),
    );
  }

  Widget _buildOrderThumbnailStrip(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    const maxVisible = 4;
    final visibleItems = items.take(maxVisible).toList();
    final hiddenCount = items.length - visibleItems.length;

    return Row(
      children: [
        for (var index = 0; index < visibleItems.length; index++) ...[
          if (index > 0) const SizedBox(width: 6),
          _orderItemThumb(visibleItems[index], size: 42),
        ],
        if (hiddenCount > 0) ...[
          const SizedBox(width: 8),
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorAppBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: MyText(
              text: '+$hiddenCount',
              color: Colors.white70,
              fontsize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOrderLineItem({
    required String orderId,
    required String? orderStatus,
    required Map<String, dynamic> item,
    required List<Map<String, dynamic>> productReturns,
  }) {
    final isFullyCancelled = _isItemFullyCancelled(item);
    final orderedQuantity = _itemOrderedQuantity(item);
    final activeQuantity = _itemActiveQuantity(item);
    final cancelledQuantity = _itemCancelledQuantity(item);
    final unitPrice = _asDouble(item['price']) > 0
        ? _asDouble(item['price'])
        : (orderedQuantity > 0
            ? _asDouble(item['lineTotal']) / orderedQuantity
            : 0);
    final activeReturnQty = _activeReturnQuantity(productReturns);
    final remainingQty = activeQuantity - activeReturnQty;
    final latestActiveReturn = _latestActiveReturn(productReturns);
    final returnStatus = latestActiveReturn?['status']?.toString();
    final discount = _asDouble(item['discount']);
    final cancelledLineTotal = unitPrice * cancelledQuantity;

    final content = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorAppBackground.withValues(
          alpha: isFullyCancelled ? 0.35 : 0.55,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFullyCancelled ? Colors.white24 : Colors.white10,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: isFullyCancelled ? 0.55 : 1,
            child: _orderItemThumb(item),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MyText(
                  text: item['name']?.toString() ?? 'Product',
                  color: isFullyCancelled ? Colors.white54 : Colors.white,
                  fontsize: 15,
                ),
                if (isFullyCancelled) ...[
                  const SizedBox(height: 6),
                  _buildStatusTag('Cancelled', Colors.redAccent),
                ] else if (returnStatus == 'requested') ...[
                  const SizedBox(height: 6),
                  _buildStatusTag('Return requested', Colors.redAccent),
                ],
                const SizedBox(height: 6),
                MyText(
                  text: isFullyCancelled
                      ? '${_money.format(unitPrice)} each · Cancelled qty $cancelledQuantity'
                      : '${_money.format(unitPrice)} each · Qty $activeQuantity',
                  color: Colors.white54,
                  fontsize: 12,
                ),
                if (discount > 0 && !isFullyCancelled) ...[
                  const SizedBox(height: 4),
                  MyText(
                    text: '${discount.round()}% discount applied',
                    color: colorOrange,
                    fontsize: 11,
                  ),
                ],
                const SizedBox(height: 4),
                MyText(
                  text: isFullyCancelled
                      ? 'Cancelled total: ${_money.format(cancelledLineTotal)}'
                      : 'Line total: ${_money.format(_asDouble(item['lineTotal']))}',
                  color: isFullyCancelled ? Colors.white38 : colorIceBlue,
                  fontsize: 13,
                ),
                if (!isFullyCancelled &&
                    returnStatus != null &&
                    returnStatus.isNotEmpty &&
                    returnStatus != 'requested') ...[
                  const SizedBox(height: 6),
                  MyText(
                    text:
                        '${_returnStatusLabel(returnStatus)} · qty ${_asInt(latestActiveReturn?['quantity'], 1)}',
                    color: _returnStatusColor(returnStatus),
                    fontsize: 12,
                  ),
                ] else if (!isFullyCancelled &&
                    remainingQty < activeQuantity &&
                    returnStatus != 'requested') ...[
                  const SizedBox(height: 6),
                  MyText(
                    text:
                        '$activeReturnQty in return · $remainingQty available to return',
                    color: Colors.orangeAccent,
                    fontsize: 12,
                  ),
                ],
                if (!isFullyCancelled) ...[
                  const SizedBox(height: 6),
                  MyText(
                    text: returnStatus == 'requested'
                        ? 'Tap to view or cancel return request'
                        : remainingQty <= 0
                            ? 'Tap to view return details'
                            : 'Tap to request a return',
                    color: Colors.white38,
                    fontsize: 11,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (isFullyCancelled) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showReturnDialog(
          orderId: orderId,
          orderStatus: orderStatus,
          item: item,
          existingReturns: productReturns,
        ),
        child: content,
      ),
    );
  }

  Widget _buildOrderCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final orderId = doc.id;
    final items = (data['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final total = _asDouble(data['total']);
    final status = data['status']?.toString();
    final itemCount = _orderItemCount(items);
    final productLines = items.length;

    return Card(
      color: colorAppBar,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.white12),
      ),
      child: FutureBuilder<
          (List<Map<String, dynamic>>, Map<String, List<Map<String, dynamic>>>)>(
        future: _loadOrderDetails(orderId, items),
        builder: (context, snapshot) {
          final enrichedItems = snapshot.data?.$1 ?? items;
          final returnsByProduct = snapshot.data?.$2 ?? {};
          final summary = _orderItemsSummary(enrichedItems);
          final hasReturnRequested = _orderHasReturnRequested(returnsByProduct);

          return ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            iconColor: colorIceBlue,
            collapsedIconColor: Colors.white54,
            title: MyText(
              text: _formatOrderDate(data['createdAt']),
              color: Colors.white,
              fontsize: 16,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    enrichedItems.every((item) => _itemImageUrl(item) == null))
                  const SizedBox(
                    height: 42,
                    width: 42,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  _buildOrderThumbnailStrip(enrichedItems),
                const SizedBox(height: 10),
                MyText(
                  text: summary,
                  color: Colors.white,
                  fontsize: 14,
                ),
                const SizedBox(height: 6),
                MyText(
                  text:
                      '$productLines product${productLines == 1 ? '' : 's'} · '
                      '$itemCount item${itemCount == 1 ? '' : 's'} · '
                      '${_money.format(total)}',
                  color: colorIceBlue,
                  fontsize: 13,
                ),
                if (data['shippingAmount'] != null) ...[
                  const SizedBox(height: 4),
                  MyText(
                    text:
                        'Delivery ${_money.format(_asDouble(data['shippingAmount']))}'
                        '${data['shippingRate'] is Map && (data['shippingRate'] as Map)['name'] != null ? ' · ${(data['shippingRate'] as Map)['name']}' : ''}',
                    color: Colors.white54,
                    fontsize: 12,
                  ),
                ],
                if ((data['trackingUrl'] ?? data['trackingReference']) != null &&
                    '${data['trackingUrl'] ?? data['trackingReference']}'
                        .isNotEmpty) ...[
                  const SizedBox(height: 4),
                  MyText(
                    text: data['trackingUrl'] != null
                        ? 'Track with Bob Go'
                        : 'Tracking: ${data['trackingReference']}',
                    color: colorIceBlue,
                    fontsize: 12,
                  ),
                ],
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildStatusTag(
                          _orderStatusLabel(status),
                          _orderStatusColor(status),
                        ),
                        if (hasReturnRequested)
                          _buildStatusTag(
                            'Return requested',
                            Colors.redAccent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    MyText(
                      text:
                          'Order #${orderId.length > 8 ? orderId.substring(0, 8) : orderId}',
                      color: Colors.white38,
                      fontsize: 11,
                    ),
                  ],
                ),
              ],
            ),
            children: [
              if (_canExportBobGo(status)) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _exportOrderCsv(orderId, data),
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Download Bob Go CSV'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorIceBlue,
                      side: const BorderSide(color: colorIceBlue),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MyText(
                    text: 'Items in this order',
                    color: Colors.white70,
                    fontsize: 13,
                  ),
                ),
              ),
              if (enrichedItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: MyText(
                    text: 'No items found for this order.',
                    color: Colors.white54,
                    fontsize: 13,
                  ),
                )
              else
                Column(
                  children: enrichedItems.map((item) {
                    final productId = item['productId']?.toString() ?? '';
                    final isCancelledHistory =
                        item['isCancelledHistoryTile'] == true;
                    return _buildOrderLineItem(
                      orderId: orderId,
                      orderStatus: status,
                      item: item,
                      productReturns: isCancelledHistory
                          ? const []
                          : returnsByProduct[productId] ?? [],
                    );
                  }).toList(),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersRef = _ordersRef;

    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle('Order History'),
        actions: [
          if (context.watch<UserDataService>().userdata?.isDeveloper == true)
            IconButton(
              tooltip: 'Export paid shop orders for Bob Go',
              icon: const Icon(Icons.local_shipping_outlined),
              onPressed: _exportAllShopSalesCsv,
            ),
        ],
      ),
      body: ordersRef == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.login, color: Colors.white38, size: 40),
                  const SizedBox(height: 12),
                  const MyText(
                    text: 'Please log in to view your orders.',
                    color: Colors.white54,
                    fontsize: 15,
                  ),
                ],
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ordersRef
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: myProgressCircle());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: MyText(
                        text: 'Could not load orders.\n${snapshot.error}',
                        color: Colors.white54,
                        fontsize: 14,
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long,
                            color: Colors.white38, size: 40),
                        const SizedBox(height: 12),
                        const MyText(
                          text: 'No orders yet',
                          color: Colors.white,
                          fontsize: 16,
                        ),
                        const SizedBox(height: 8),
                        const MyText(
                          text: 'Products you buy in the Online Shop will appear here.',
                          color: Colors.white54,
                          fontsize: 13,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) => _buildOrderCard(docs[index]),
                );
              },
            ),
    );
  }
}
