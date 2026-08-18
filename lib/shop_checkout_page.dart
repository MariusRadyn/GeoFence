import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/address_suggestions.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ShopCheckoutPage extends StatefulWidget {
  const ShopCheckoutPage({super.key});

  @override
  State<ShopCheckoutPage> createState() => _ShopCheckoutPageState();
}

class _ShopCheckoutPageState extends State<ShopCheckoutPage> {
  final _money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _street = TextEditingController();
  final _suburb = TextEditingController();
  final _city = TextEditingController();
  final _postal = TextEditingController();
  final _streetFocus = FocusNode();
  final _suggest = AddressSuggestionService();

  bool _loadingRates = false;
  bool _paying = false;
  bool _applyingSuggestion = false;
  List<AddressSuggestion> _suggestions = [];
  List<Map<String, dynamic>> _rates = [];
  Map<String, dynamic>? _selectedRate;
  Timer? _suggestTimer;

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _email.text = user?.email ?? '';
    _name.text = user?.displayName ?? '';
    _street.addListener(_onStreetChanged);
    _loadSavedAddress();
    _suggest.ensureLocation();
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _street.removeListener(_onStreetChanged);
    _streetFocus.dispose();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _street.dispose();
    _suburb.dispose();
    _city.dispose();
    _postal.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddress() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _name.text = prefs.getString('shop_ship_name') ?? _name.text;
      _phone.text = prefs.getString('shop_ship_phone') ?? '';
      _street.text = prefs.getString('shop_ship_street') ?? '';
      _suburb.text = prefs.getString('shop_ship_suburb') ?? '';
      _city.text = prefs.getString('shop_ship_city') ?? '';
      _postal.text = prefs.getString('shop_ship_code') ?? '';
    });
  }

  Future<void> _saveAddress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shop_ship_name', _name.text.trim());
    await prefs.setString('shop_ship_phone', _phone.text.trim());
    await prefs.setString('shop_ship_street', _street.text.trim());
    await prefs.setString('shop_ship_suburb', _suburb.text.trim());
    await prefs.setString('shop_ship_city', _city.text.trim());
    await prefs.setString('shop_ship_code', _postal.text.trim());
  }

  void _onStreetChanged() {
    if (_applyingSuggestion) return;
    _suggestTimer?.cancel();
    final query = _street.text.trim();
    if (query.length < 3) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 280), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    final list = await _suggest.search(query);
    if (!mounted || _street.text.trim() != query) return;
    setState(() => _suggestions = list);
  }

  Future<void> _applySuggestion(AddressSuggestion suggestion) async {
    final detailed = await _suggest.details(suggestion);
    if (!mounted) return;
    _applyingSuggestion = true;
    setState(() {
      if (detailed.street.isNotEmpty) _street.text = detailed.street;
      if (detailed.suburb.isNotEmpty) _suburb.text = detailed.suburb;
      if (detailed.city.isNotEmpty) _city.text = detailed.city;
      if (detailed.postalCode.isNotEmpty) _postal.text = detailed.postalCode;
      _suggestions = [];
    });
    _streetFocus.unfocus();
    _applyingSuggestion = false;
  }

  Map<String, dynamic> _destination() => {
        'street': _street.text.trim(),
        'suburb': _suburb.text.trim(),
        'city': _city.text.trim(),
        'postalCode': _postal.text.trim(),
      };

  Map<String, dynamic> _shippingPayload() => {
        'fullName': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        ..._destination(),
      };

  double get _shippingAmount =>
      (_selectedRate?['amount'] as num?)?.toDouble() ?? 0;

  String _callableError(Object e) {
    if (e is FirebaseFunctionsException) {
      return e.message ?? e.code;
    }
    return '$e';
  }

  Future<void> _loadRates(ShopCartService cart) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loadingRates = true;
      _rates = [];
      _selectedRate = null;
    });
    try {
      await _saveAddress();
      final callable = _functions.httpsCallable('getBobGoRates');
      final result = await callable.call({
        'destination': _destination(),
        'fullName': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'cartTotal': cart.total,
        'items': cart.items
            .map(
              (i) => {
                'productId': i.product.id,
                'name': i.product.name,
                'quantity': i.quantity,
                'price': i.unitPrice,
                'weightKg': i.product.weightKg,
                'lengthCm': i.product.lengthCm,
                'widthCm': i.product.widthCm,
                'heightCm': i.product.heightCm,
              },
            )
            .toList(),
      });
      final raw = result.data;
      final list = (raw is Map && raw['rates'] is List)
          ? List<Map<String, dynamic>>.from(
              (raw['rates'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _rates = list;
        _selectedRate = list.isEmpty ? null : list.first;
      });
      if (list.isEmpty) {
        MyGlobalMessage.show(
          'Shipping',
          'No Bob Go rates for this address. Check suburb and postal code.',
          MyMessageType.warning,
        );
      }
    } catch (e) {
      MyGlobalMessage.show('Bob Go', _callableError(e), MyMessageType.error);
    } finally {
      if (mounted) setState(() => _loadingRates = false);
    }
  }

  Future<void> _pay(ShopCartService cart) async {
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
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRate == null) {
      MyGlobalMessage.show(
        'Shipping',
        'Get Bob Go rates and select a delivery option first.',
        MyMessageType.warning,
      );
      return;
    }

    setState(() => _paying = true);
    try {
      await _saveAddress();
      final shipping = _shippingAmount;
      final subtotal = cart.total;
      final total = subtotal + shipping;
      final orderRef = FirebaseFirestore.instance
          .collection(collectionUsers)
          .doc(user.uid)
          .collection(collectionShopOrders)
          .doc();

      final items = cart.items
          .map(
            (i) => {
              'productId': i.product.id,
              'name': i.product.name,
              'catalogPrice': i.product.price,
              'price': i.unitPrice,
              'discount': i.product.discount,
              'quantity': i.quantity,
              'orderedQuantity': i.quantity,
              'cancelledQuantity': 0,
              'lineTotal': i.lineTotal,
              'imageUrl': i.product.primaryImageUrl,
              'imageAsset': i.product.imageAsset,
              'weightKg': i.product.weightKg,
              'lengthCm': i.product.lengthCm,
              'widthCm': i.product.widthCm,
              'heightCm': i.product.heightCm,
            },
          )
          .toList();

      await orderRef.set({
        'orderId': orderRef.id,
        'userId': user.uid,
        'email': user.email,
        'items': items,
        'subtotal': subtotal,
        'shippingAmount': shipping,
        'total': total,
        'currency': 'ZAR',
        'status': 'pending_payment',
        'paymentProvider': 'bob_pay',
        'shippingProvider': 'bob_go',
        'shipping': _shippingPayload(),
        'shippingRate': _selectedRate,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final callable = _functions.httpsCallable('createBobPayCheckout');
      final result = await callable.call({'orderId': orderRef.id});
      final data = result.data;
      final url = data is Map ? data['checkoutUrl']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('No Bob Pay checkout URL returned.');
      }

      cart.clear();
      if (!mounted) return;
      final uri = Uri.parse(url);
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        MyGlobalMessage.show(
          'Bob Pay',
          'Could not open checkout. Copy this URL:\n$url',
          MyMessageType.warning,
        );
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      MyGlobalMessage.show(
        'Bob Pay',
        'Complete payment in the browser. Your order will update when Bob Pay confirms it.',
        MyMessageType.info,
      );
    } catch (e) {
      MyGlobalMessage.show('Checkout', _callableError(e), MyMessageType.error);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ShopCartService>(
      builder: (context, cart, _) {
        final total = cart.total + _shippingAmount;
        return Scaffold(
          backgroundColor: colorAppBackground,
          appBar: AppBar(
            backgroundColor: colorAppBar,
            foregroundColor: Colors.white,
            title: myAppbarTitle('Checkout'),
          ),
          body: cart.isEmpty
              ? const Center(
                  child: MyText(
                    text: 'Your basket is empty',
                    color: Colors.white54,
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    children: [
                      const MyText(
                        text: 'Delivery address (South Africa)',
                        color: Colors.white,
                        fontsize: 16,
                      ),
                      const SizedBox(height: 12),
                      MyTextFormField(
                        controller: _name,
                        labelText: 'Full name',
                        backgroundColor: colorAppBar,
                        foregroundColor: Colors.white,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      MyTextFormField(
                        controller: _phone,
                        labelText: 'Mobile number',
                        hintText: '0821234567',
                        inputType: TextInputType.phone,
                        backgroundColor: colorAppBar,
                        foregroundColor: Colors.white,
                        validator: (v) =>
                            (v == null || v.trim().length < 10)
                                ? 'Enter a valid number'
                                : null,
                      ),
                      const SizedBox(height: 10),
                      MyTextFormField(
                        controller: _email,
                        labelText: 'Email',
                        inputType: TextInputType.emailAddress,
                        backgroundColor: colorAppBar,
                        foregroundColor: Colors.white,
                        validator: (v) =>
                            (v == null || !v.contains('@')) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      MyTextFormField(
                        controller: _street,
                        focusNode: _streetFocus,
                        labelText: 'Street address',
                        hintText: 'Start typing — nearby addresses appear',
                        backgroundColor: colorAppBar,
                        foregroundColor: Colors.white,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      if (_suggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4, bottom: 6),
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            color: colorAppBar,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Material(
                              color: Colors.transparent,
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                primary: false,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.manual,
                                itemCount: _suggestions.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: Colors.white12,
                                ),
                                itemBuilder: (_, i) {
                                  final suggestion = _suggestions[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.place_outlined,
                                      color: colorIceBlue,
                                      size: 20,
                                    ),
                                    title: Text(
                                      suggestion.label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                    onTap: () => _applySuggestion(suggestion),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      MyTextFormField(
                        controller: _suburb,
                        labelText: 'Suburb',
                        backgroundColor: colorAppBar,
                        foregroundColor: Colors.white,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      MyTextFormField(
                        controller: _city,
                        labelText: 'City',
                        backgroundColor: colorAppBar,
                        foregroundColor: Colors.white,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      MyTextFormField(
                        controller: _postal,
                        labelText: 'Postal code',
                        inputType: TextInputType.number,
                        backgroundColor: colorAppBar,
                        foregroundColor: Colors.white,
                        validator: (v) =>
                            (v == null || v.trim().length < 4) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorIceBlue,
                            side: const BorderSide(color: colorIceBlue),
                          ),
                          onPressed:
                              _loadingRates ? null : () => _loadRates(cart),
                          child: _loadingRates
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorIceBlue,
                                  ),
                                )
                              : const Text('Get Bob Go delivery rates'),
                        ),
                      ),
                      if (_rates.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const MyText(
                          text: 'Delivery option',
                          color: Colors.white,
                          fontsize: 16,
                        ),
                        const SizedBox(height: 8),
                        ..._rates.map((rate) {
                          final selected = _selectedRate?['id'] == rate['id'] &&
                              _selectedRate?['name'] == rate['name'];
                          return RadioListTile<bool>(
                            value: true,
                            groupValue: selected,
                            onChanged: (_) =>
                                setState(() => _selectedRate = rate),
                            activeColor: colorOrange,
                            title: MyText(
                              text:
                                  '${rate['name']} · ${_money.format(asNumber(rate['amount']))}',
                              color: Colors.white,
                              fontsize: 14,
                            ),
                            subtitle: (rate['eta']?.toString().isNotEmpty ==
                                    true)
                                ? MyText(
                                    text: '${rate['eta']}',
                                    color: Colors.white54,
                                    fontsize: 12,
                                  )
                                : null,
                          );
                        }),
                      ],
                      const SizedBox(height: 20),
                      _totalsRow('Items', cart.total),
                      _totalsRow('Delivery', _shippingAmount),
                      const Divider(color: Colors.white24),
                      _totalsRow('To pay', total, bold: true),
                    ],
                  ),
                ),
          bottomNavigationBar: cart.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorOrange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _paying ? null : () => _pay(cart),
                        child: _paying
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Pay ${_money.format(total)} with Bob Pay',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  double asNumber(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  Widget _totalsRow(String label, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          MyText(
            text: label,
            color: bold ? Colors.white : Colors.white70,
            fontsize: bold ? 16 : 14,
          ),
          const Spacer(),
          MyText(
            text: _money.format(amount),
            color: bold ? Colors.white : colorIceBlue,
            fontsize: bold ? 18 : 14,
          ),
        ],
      ),
    );
  }
}
