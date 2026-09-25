import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Lists the signed-in user's PayFast subscriptions and allows cancellation.
class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  final _money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
  final _dateFormat = DateFormat('dd MMM yyyy');
  final Set<String> _cancelling = {};

  /// Default: Active only.
  bool _showActiveOnly = true;

  String? get _uid => currentDataOwnerUid();

  CollectionReference<Map<String, dynamic>>? get _ordersRef {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid)
        .collection(collectionShopOrders);
  }

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: cloudFunctionsRegion);

  bool _isSubscriptionOrder(Map<String, dynamic> data) {
    if (data['hasSubscription'] == true) return true;
    final token = (data['subscriptionToken'] ?? data['payfastToken'] ?? '')
        .toString()
        .trim();
    if (token.isNotEmpty) return true;
    final monthly = (data['subscriptionMonthly'] is num)
        ? (data['subscriptionMonthly'] as num).toDouble()
        : double.tryParse('${data['subscriptionMonthly']}') ?? 0;
    return monthly > 0;
  }

  String _tokenOf(Map<String, dynamic> data) {
    return (data['subscriptionToken'] ?? data['payfastToken'] ?? '')
        .toString()
        .trim();
  }

  String _statusLabel(Map<String, dynamic> data) {
    final status = (data['subscriptionStatus'] ?? '').toString().toLowerCase();
    if (status == 'cancelled' || status == 'canceled') return 'Cancelled';
    final token = _tokenOf(data);
    final orderStatus = (data['status'] ?? '').toString();
    if (token.isEmpty) {
      if (orderStatus == 'pending_payment') return 'Awaiting payment';
      return 'Pending token';
    }
    return 'Active';
  }

  Color _statusColor(String label) {
    return switch (label) {
      'Active' => Colors.greenAccent,
      'Cancelled' => Colors.redAccent,
      'Awaiting payment' => Colors.orangeAccent,
      _ => Colors.white54,
    };
  }

  String _formatDate(dynamic value) {
    if (value is Timestamp) return _dateFormat.format(value.toDate());
    return '—';
  }

  String _callableError(Object e) {
    if (e is FirebaseFunctionsException) {
      return e.message?.trim().isNotEmpty == true
          ? e.message!
          : (e.code);
    }
    return e.toString();
  }

  Future<void> _copyToken(String token) async {
    await Clipboard.setData(ClipboardData(text: token));
    MyGlobalMessage.show(
      'Token copied',
      'Subscription token copied to clipboard.',
      MyMessageType.info,
    );
  }

  Future<void> _cancelSubscription({
    required String orderId,
    required String token,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorAppBar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.blue, width: 2),
        ),
        title: const Text(
          'Cancel subscription?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This cancels recurring billing on PayFast for token:\n\n$token\n\n'
          'The subscription will still be active until the last day of the month.\n\n'
          'This cannot be undone from the app.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Cancel subscription'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling.add(orderId));
    try {
      final callable = _functions.httpsCallable('cancelPayfastSubscription');
      await callable.call({'orderId': orderId});
      if (!mounted) return;
      await context
          .read<MonitorSettingsService>()
          .clearSubscriptionFromOrder(orderId);
      if (!mounted) return;
      MyGlobalMessage.show(
        'Subscription',
        'Subscription cancelled on PayFast.',
        MyMessageType.success,
      );
    } catch (e) {
      MyGlobalMessage.show(
        'Cancel failed',
        _callableError(e),
        MyMessageType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _cancelling.remove(orderId));
      }
    }
  }

  String? _wheelNameForOrder(
    MonitorSettingsService monitors,
    String orderId,
  ) {
    final id = orderId.trim();
    if (id.isEmpty) return null;
    for (final m in monitors.lstMonitors) {
      if (m.subscriptionOrderId.trim() == id) {
        final name = m.monitorName.trim();
        if (name.isNotEmpty && name != 'New Item') return name;
        final mid = m.monitorId.trim();
        if (mid.isNotEmpty && mid != 'none') return 'Wheel $mid';
        return 'Distance Wheel';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ref = _ordersRef;
    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle('Subscriptions'),
        actions: [
          PopupMenuButton<bool>(
            tooltip: 'Filter',
            icon: const Icon(Icons.filter_list),
            color: colorAppBar,
            onSelected: (activeOnly) {
              setState(() => _showActiveOnly = activeOnly);
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<bool>(
                value: true,
                checked: _showActiveOnly,
                child: const Text('Active', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<bool>(
                value: false,
                checked: !_showActiveOnly,
                child: const Text('All', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
      body: _uid == null
          ? const Center(
              child: MyText(
                text: 'Please log in to view subscriptions.',
                color: Colors.white54,
              ),
            )
          : Consumer<MonitorSettingsService>(
              builder: (context, monitors, _) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: ref!
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: MyText(
                            text:
                                'Could not load subscriptions.\n${snap.error}',
                            color: Colors.redAccent,
                          ),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(
                        child:
                            CircularProgressIndicator(color: colorOrange),
                      );
                    }
                    final docs = snap.data!.docs
                        .where((d) => _isSubscriptionOrder(d.data()))
                        .where((d) {
                          if (!_showActiveOnly) return true;
                          return _statusLabel(d.data()) == 'Active';
                        })
                        .toList();
                    if (docs.isEmpty) {
                      return Center(
                        child: MyText(
                          text: _showActiveOnly
                              ? 'No active subscriptions.'
                              : 'No subscriptions yet.',
                          color: Colors.white54,
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final orderId =
                            (data['orderId'] ?? doc.id).toString();
                        final token = _tokenOf(data);
                        final monthly = (data['subscriptionMonthly'] is num)
                            ? (data['subscriptionMonthly'] as num)
                                .toDouble()
                            : double.tryParse(
                                  '${data['subscriptionMonthly']}',
                                ) ??
                                0;
                        final status = _statusLabel(data);
                        final statusColor = _statusColor(status);
                        final canCancel =
                            token.isNotEmpty && status == 'Active';
                        final busy = _cancelling.contains(orderId);
                        final items = (data['items'] is List)
                            ? (data['items'] as List)
                            : const [];
                        final names = items
                            .map((e) =>
                                (e is Map ? e['name'] : null)?.toString())
                            .whereType<String>()
                            .where((n) => n.trim().isNotEmpty)
                            .take(3)
                            .join(', ');
                        final wheelName =
                            _wheelNameForOrder(monitors, orderId);
                        final isAvailable =
                            status == 'Active' && wheelName == null;

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorAppBar,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      names.isEmpty
                                          ? 'Order $orderId'
                                          : names,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border:
                                          Border.all(color: statusColor),
                                    ),
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (isAvailable)
                                const Text(
                                  'Available',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                )
                              else if (wheelName != null)
                                Text(
                                  'Linked to: $wheelName',
                                  style: const TextStyle(
                                    color: colorIceBlue,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                )
                              else if (status != 'Active')
                                Text(
                                  status == 'Cancelled'
                                      ? 'Not available'
                                      : 'Not ready to assign',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              const SizedBox(height: 10),
                              if (monthly > 0)
                                Text(
                                  '${_money.format(monthly)} / month',
                                  style: const TextStyle(
                                    color: colorOrange,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                'Order: $orderId',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'Started: ${_formatDate(data['paidAt'] ?? data['createdAt'])}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              if (status == 'Cancelled')
                                Text(
                                  'Cancelled: ${_formatDate(data['subscriptionCancelledAt'])}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              const SizedBox(height: 10),
                              const Text(
                                'Token ID',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      token.isEmpty
                                          ? 'Not available yet'
                                          : token,
                                      style: TextStyle(
                                        color: token.isEmpty
                                            ? Colors.white38
                                            : colorIceBlue,
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  if (token.isNotEmpty)
                                    IconButton(
                                      tooltip: 'Copy token',
                                      onPressed: () => _copyToken(token),
                                      icon: const Icon(
                                        Icons.copy,
                                        size: 18,
                                        color: Colors.white70,
                                      ),
                                    ),
                                ],
                              ),
                              if (canCancel) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 42,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.redAccent,
                                      side: const BorderSide(
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () => _cancelSubscription(
                                              orderId: orderId,
                                              token: token,
                                            ),
                                    child: busy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.redAccent,
                                            ),
                                          )
                                        : const Text(
                                            'Cancel subscription',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
