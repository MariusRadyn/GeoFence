import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/address_suggestions.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/shop_subscribe_page.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ShopCheckoutPage extends StatefulWidget {
  final ShopSubscribeDetails? subscribeDetails;

  const ShopCheckoutPage({super.key, this.subscribeDetails});

  @override
  State<ShopCheckoutPage> createState() => _ShopCheckoutPageState();
}

class _ShopCheckoutPageState extends State<ShopCheckoutPage> {
  static const double _flatShipping = 150;

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

  bool _paying = false;
  bool _applyingSuggestion = false;
  bool _loadingSuggestions = false;
  List<AddressSuggestion> _suggestions = [];
  Timer? _suggestTimer;
  Timer? _hideSuggestionsTimer;

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: cloudFunctionsRegion);

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    final sub = widget.subscribeDetails;
    _email.text = sub?.email.isNotEmpty == true
        ? sub!.email
        : (user?.email ?? '');
    _name.text = sub?.fullName.isNotEmpty == true
        ? sub!.fullName
        : (user?.displayName ?? '');
    if (sub != null && sub.phone.isNotEmpty) {
      _phone.text = sub.phone;
    }
    _street.addListener(_onStreetChanged);
    _streetFocus.addListener(_onStreetFocusChanged);
    _loadSavedAddress();
    _suggest.ensureLocation();
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _hideSuggestionsTimer?.cancel();
    _street.removeListener(_onStreetChanged);
    _streetFocus.removeListener(_onStreetFocusChanged);
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

  String _shipKey(String base) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return uid.isEmpty ? base : '${base}_$uid';
  }

  Future<void> _loadSavedAddress() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    final sub = widget.subscribeDetails;
    _applyingSuggestion = true;
    setState(() {
      // Prefer subscribe form / signed-in user over any stale saved email.
      if (sub != null && sub.email.isNotEmpty) {
        _email.text = sub.email;
      } else {
        _email.text = user?.email?.trim() ?? _email.text;
      }
      if (sub == null || sub.fullName.isEmpty) {
        _name.text =
            prefs.getString(_shipKey('shop_ship_name')) ?? _name.text;
      }
      if (sub == null || sub.phone.isEmpty) {
        _phone.text =
            prefs.getString(_shipKey('shop_ship_phone')) ?? _phone.text;
      }
      _street.text = prefs.getString(_shipKey('shop_ship_street')) ?? '';
      _suburb.text = prefs.getString(_shipKey('shop_ship_suburb')) ?? '';
      _city.text = prefs.getString(_shipKey('shop_ship_city')) ?? '';
      _postal.text = prefs.getString(_shipKey('shop_ship_code')) ?? '';
      _suggestions = [];
      _loadingSuggestions = false;
    });
    _applyingSuggestion = false;
  }

  Future<void> _saveAddress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shipKey('shop_ship_name'), _name.text.trim());
    await prefs.setString(_shipKey('shop_ship_phone'), _phone.text.trim());
    await prefs.setString(_shipKey('shop_ship_street'), _street.text.trim());
    await prefs.setString(_shipKey('shop_ship_suburb'), _suburb.text.trim());
    await prefs.setString(_shipKey('shop_ship_city'), _city.text.trim());
    await prefs.setString(_shipKey('shop_ship_code'), _postal.text.trim());
  }

  void _clearSuggestions() {
    if (_suggestions.isEmpty && !_loadingSuggestions) return;
    setState(() {
      _suggestions = [];
      _loadingSuggestions = false;
    });
  }

  void _onStreetFocusChanged() {
    if (_streetFocus.hasFocus) {
      _hideSuggestionsTimer?.cancel();
      final query = _street.text.trim();
      if (query.length >= 3) {
        _suggestTimer?.cancel();
        _suggestTimer = Timer(const Duration(milliseconds: 200), () {
          _fetchSuggestions(query);
        });
      }
      return;
    }
    // Delay hide so a tap on a suggestion can register before the list disappears.
    _suggestTimer?.cancel();
    _hideSuggestionsTimer?.cancel();
    _hideSuggestionsTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _applyingSuggestion || _streetFocus.hasFocus) return;
      _clearSuggestions();
    });
  }

  void _onStreetChanged() {
    if (_applyingSuggestion) return;
    if (!_streetFocus.hasFocus) return;
    _hideSuggestionsTimer?.cancel();
    _suggestTimer?.cancel();
    final query = _street.text.trim();
    if (query.length < 3) {
      _clearSuggestions();
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 280), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!_streetFocus.hasFocus) return;
    if (mounted) setState(() => _loadingSuggestions = true);
    try {
      final list = await _suggest.search(query);
      if (!mounted || _street.text.trim() != query || !_streetFocus.hasFocus) {
        if (mounted) _clearSuggestions();
        return;
      }
      setState(() {
        _suggestions = list;
        _loadingSuggestions = false;
      });
    } catch (_) {
      if (!mounted || _street.text.trim() != query) return;
      _clearSuggestions();
    }
  }

  Future<void> _applySuggestion(AddressSuggestion suggestion) async {
    _hideSuggestionsTimer?.cancel();
    _suggestTimer?.cancel();
    _applyingSuggestion = true;
    final typedStreet = _street.text.trim();

    // Fill immediately from the tapped suggestion (works offline of details).
    setState(() {
      if (suggestion.street.isNotEmpty) {
        _street.text = _keepHouseNumber(typedStreet, suggestion.street);
      } else if (suggestion.label.isNotEmpty) {
        _street.text = _keepHouseNumber(
          typedStreet,
          suggestion.label.split(',').first.trim(),
        );
      }
      if (suggestion.suburb.isNotEmpty) _suburb.text = suggestion.suburb;
      if (suggestion.city.isNotEmpty) _city.text = suggestion.city;
      if (suggestion.postalCode.isNotEmpty) {
        _postal.text = suggestion.postalCode;
      }
      _suggestions = [];
      _loadingSuggestions = false;
    });

    try {
      final detailed = await _suggest.details(suggestion);
      if (!mounted) return;
      setState(() {
        if (detailed.street.isNotEmpty) {
          _street.text = _keepHouseNumber(typedStreet, detailed.street);
        }
        if (detailed.suburb.isNotEmpty) _suburb.text = detailed.suburb;
        if (detailed.city.isNotEmpty) _city.text = detailed.city;
        if (detailed.postalCode.isNotEmpty) {
          _postal.text = detailed.postalCode;
        }
      });
    } finally {
      if (mounted) _streetFocus.unfocus();
      _applyingSuggestion = false;
    }
  }

  /// Suggestions often return the road name only; keep a house number the user typed.
  String _keepHouseNumber(String typed, String suggested) {
    final typedTrim = typed.trim();
    final suggestedTrim = suggested.trim();
    if (suggestedTrim.isEmpty) return typedTrim;
    if (typedTrim.isEmpty) return suggestedTrim;
    // Suggestion already includes a number (e.g. "46 Pope Ellis Dr").
    if (RegExp(r'^\d').hasMatch(suggestedTrim)) return suggestedTrim;

    final match = RegExp(
      r'^(\d+[A-Za-z]?(?:\s*[-/]\s*\d+[A-Za-z]?)?)',
    ).firstMatch(typedTrim);
    if (match == null) return suggestedTrim;

    final number = match.group(1)!.trim();
    if (suggestedTrim.toLowerCase().startsWith(number.toLowerCase())) {
      return suggestedTrim;
    }
    return '$number $suggestedTrim';
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

  Map<String, dynamic> _shippingRateFor(double amount) => {
        'id': amount <= 0 ? 'free_delivery' : 'flat_150',
        'name': amount <= 0 ? 'Free delivery' : 'Standard delivery',
        'amount': amount,
        'eta': amount <= 0 ? 'Free delivery' : 'Flat rate',
      };

  double _shippingForCart(ShopCartService cart) =>
      cart.needsShipping ? _flatShipping : 0;

  String _callableError(Object e) {
    if (e is FirebaseFunctionsException) {
      return e.message ?? e.code;
    }
    return '$e';
  }

  bool _payingDialogVisible = false;

  void _showPayingDialog() {
    if (_payingDialogVisible || !mounted) return;
    _payingDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.blue, width: 2),
          ),
          backgroundColor: colorAppTitle,
          title: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorOrange,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: MyText(text: 'Payment', color: Colors.white),
              ),
            ],
          ),
          content: const MyText(
            text: 'Preparing checkout…',
            color: Colors.grey,
            fontsize: 18,
          ),
        ),
      ),
    ).whenComplete(() {
      _payingDialogVisible = false;
    });
  }

  void _hidePayingDialog() {
    if (!_payingDialogVisible || !mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
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

    setState(() => _paying = true);
    _showPayingDialog();
    try {
      await _saveAddress();
      final shipping = _shippingForCart(cart);
      final subtotal = cart.total;
      final subscriptionMonthly = cart.subscriptionMonthlyTotal;
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
              'freeDelivery': i.product.freeDelivery,
              'subscriptionMonthly': i.product.subscriptionMonthly,
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
        'subscriptionMonthly': subscriptionMonthly,
        if (widget.subscribeDetails != null)
          'subscription': {
            ...widget.subscribeDetails!.toMap(),
            'amount': subscriptionMonthly,
          },
        'total': total,
        'currency': 'ZAR',
        'status': 'pending_payment',
        'paymentProvider': 'payfast',
        'shippingProvider': shipping <= 0 ? 'free' : 'flat',
        'shipping': _shippingPayload(),
        'shippingRate': _shippingRateFor(shipping),
        'createdAt': FieldValue.serverTimestamp(),
      });

      final callable = _functions.httpsCallable('createPayfastCheckout');
      final result = await callable.call({'orderId': orderRef.id});
      final data = result.data;
      final url = data is Map ? data['checkoutUrl']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('No checkout URL returned.');
      }

      cart.clear();
      if (!mounted) return;
      final uri = Uri.parse(url);
      var opened = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened) {
        opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
      _hidePayingDialog();
      if (!opened) {
        MyGlobalMessage.show(
          'Payment',
          'Could not open checkout. Copy this URL:\n$url',
          MyMessageType.warning,
        );
        return;
      }
      if (!mounted) return;
      // Return to Online Shop in this app instance (don't leave checkout stack open).
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ShopPage()),
        (route) => route.isFirst,
      );
      MyGlobalMessage.show(
        'Payment',
        'Complete payment in the browser. When done you will return to the Online Shop automatically. Your order will update when payment is confirmed.',
        MyMessageType.info,
      );
    } catch (e) {
      _hidePayingDialog();
      MyGlobalMessage.show('Checkout', _callableError(e), MyMessageType.error);
    } finally {
      if (mounted) {
        _hidePayingDialog();
        setState(() => _paying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ShopCartService>(
      builder: (context, cart, _) {
        final shipping = _shippingForCart(cart);
        final subscriptionMonthly = cart.subscriptionMonthlyTotal;
        final total = cart.total + shipping;
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
                      if (_loadingSuggestions)
                        const Padding(
                          padding: EdgeInsets.only(top: 6, bottom: 2),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorIceBlue,
                              ),
                            ),
                          ),
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
                      const SizedBox(height: 20),
                      _totalsRow('Items', cart.total),
                      _totalsRow(
                        shipping <= 0 ? 'Delivery (free)' : 'Delivery',
                        shipping,
                      ),
                      if (subscriptionMonthly > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const MyText(
                                text: 'Subscription',
                                color: Colors.white70,
                                fontsize: 14,
                              ),
                              const Spacer(),
                              MyText(
                                text:
                                    '${_money.format(subscriptionMonthly)}/mo',
                                color: colorOrange,
                                fontsize: 14,
                              ),
                            ],
                          ),
                        ),
                      const Divider(color: Colors.white24),
                      _totalsRow('To pay today', total, bold: true),
                      if (subscriptionMonthly > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: MyText(
                            text:
                                'Then ${_money.format(subscriptionMonthly)} every month',
                            color: Colors.white54,
                            fontsize: 12,
                          ),
                        ),
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
                        child: Text(
                          'Pay ${_money.format(total)}',
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
