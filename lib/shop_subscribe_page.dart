import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/shop_checkout_page.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Details collected for a PayFast monthly subscription.
class ShopSubscribeDetails {
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  /// Preferred calendar date for the subscription schedule.
  final DateTime paymentDate;
  final bool acceptedTerms;

  const ShopSubscribeDetails({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.paymentDate,
    required this.acceptedTerms,
  });

  String get fullName => '$firstName $lastName'.trim();

  /// First recurring charge is one month after [paymentDate].
  DateTime get firstChargeDate {
    final d = DateTime(paymentDate.year, paymentDate.month + 1, paymentDate.day);
    return d;
  }

  String get paymentDateYmd => _ymd(paymentDate);
  String get firstChargeYmd => _ymd(firstChargeDate);

  static String _ymd(DateTime d) {
    final yyyy = d.year.toString().padLeft(4, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  Map<String, dynamic> toMap() => {
        'firstName': firstName,
        'lastName': lastName,
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'paymentDate': paymentDateYmd,
        'firstChargeDate': firstChargeYmd,
        'frequency': 'monthly',
        'cycles': 0,
        'acceptedTerms': acceptedTerms,
      };
}

/// Form to capture subscriber details before delivery / payment.
class ShopSubscribePage extends StatefulWidget {
  const ShopSubscribePage({super.key});

  @override
  State<ShopSubscribePage> createState() => _ShopSubscribePageState();
}

class _ShopSubscribePageState extends State<ShopSubscribePage> {
  final _formKey = GlobalKey<FormState>();
  final _money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
  final _dateFmt = DateFormat('d MMM yyyy');

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  DateTime _paymentDate = DateTime.now();
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    _applyAuthUser();
    _loadSaved();
  }

  void _applyAuthUser() {
    final user = FirebaseAuth.instance.currentUser;
    _email.text = user?.email?.trim() ?? '';
    final display = (user?.displayName ?? '').trim();
    if (display.isNotEmpty) {
      final parts = display.split(RegExp(r'\s+'));
      _firstName.text = parts.first;
      if (parts.length > 1) {
        _lastName.text = parts.sublist(1).join(' ');
      } else {
        _lastName.text = '';
      }
    } else {
      _firstName.text = '';
      _lastName.text = '';
    }
    _phone.text = '';
  }

  String _key(String base) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return uid.isEmpty ? base : '${base}_$uid';
  }

  Future<void> _loadSaved() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      // Always use the signed-in account email.
      _email.text = user?.email?.trim() ?? '';

      final first = prefs.getString(_key('shop_sub_first'));
      final last = prefs.getString(_key('shop_sub_last'));
      final phone = prefs.getString(_key('shop_sub_phone'));
      if (first != null && first.trim().isNotEmpty) {
        _firstName.text = first.trim();
      }
      if (last != null && last.trim().isNotEmpty) {
        _lastName.text = last.trim();
      }
      if (phone != null) {
        _phone.text = phone.trim();
      }
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key('shop_sub_first'), _firstName.text.trim());
    await prefs.setString(_key('shop_sub_last'), _lastName.text.trim());
    await prefs.setString(_key('shop_sub_phone'), _phone.text.trim());
    // Do not persist email — always take it from the signed-in user.
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickPaymentDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate.isBefore(now) ? now : _paymentDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: colorOrange,
              surface: colorAppBar,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _paymentDate = picked);
  }

  DateTime get _firstChargeDate {
    return DateTime(
      _paymentDate.year,
      _paymentDate.month + 1,
      _paymentDate.day,
    );
  }

  Future<void> _continue(ShopCartService cart) async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      MyGlobalMessage.show(
        'Subscribe',
        'Please accept the monthly subscription terms to continue.',
        MyMessageType.warning,
      );
      return;
    }
    await _savePrefs();
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    final details = ShopSubscribeDetails(
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      email: (user?.email?.trim().isNotEmpty == true)
          ? user!.email!.trim()
          : _email.text.trim(),
      phone: _phone.text.trim(),
      paymentDate: _paymentDate,
      acceptedTerms: true,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopCheckoutPage(subscribeDetails: details),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ShopCartService>(
      builder: (context, cart, _) {
        final monthly = cart.subscriptionMonthlyTotal;
        return Scaffold(
          backgroundColor: colorAppBackground,
          appBar: AppBar(
            backgroundColor: colorAppBar,
            foregroundColor: Colors.white,
            title: myAppbarTitle('Subscribe'),
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorAppBar,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MyText(
                        text: 'Monthly subscription details',
                        color: Colors.white,
                        fontsize: 18,
                      ),
                      const SizedBox(height: 8),
                      MyText(
                        text:
                            'Amount ${_money.format(monthly)}/mo · billed monthly. '
                            'The first charge is one month after your selected payment date.',
                        color: Colors.white70,
                        fontsize: 14,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                MyTextFormField(
                  controller: _firstName,
                  labelText: 'First name',
                  labelFontSize: 14,
                  backgroundColor: colorAppBar,
                  foregroundColor: Colors.white,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 18),
                MyTextFormField(
                  controller: _lastName,
                  labelText: 'Last name',
                  labelFontSize: 14,
                  backgroundColor: colorAppBar,
                  foregroundColor: Colors.white,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 18),
                MyTextFormField(
                  controller: _email,
                  labelText: 'Email',
                  labelFontSize: 14,
                  inputType: TextInputType.emailAddress,
                  backgroundColor: colorAppBar,
                  foregroundColor: Colors.white,
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Required';
                    if (!t.contains('@') || !t.contains('.')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                MyTextFormField(
                  controller: _phone,
                  labelText: 'Mobile number',
                  labelFontSize: 14,
                  inputType: TextInputType.phone,
                  backgroundColor: colorAppBar,
                  foregroundColor: Colors.white,
                  validator: (v) {
                    final t = (v ?? '').replaceAll(RegExp(r'\s+'), '');
                    if (t.length < 10) return 'Enter a valid mobile number';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: _pickPaymentDate,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    isEmpty: false,
                    decoration: InputDecoration(
                      labelText: 'Subscription payment date',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelStyle: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: colorAppBar,
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: colorIceBlue),
                      ),
                    ),
                    child: SizedBox(
                      height: 28,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _dateFmt.format(_paymentDate),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.calendar_today,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                MyText(
                  text:
                      'First charge on ${_dateFmt.format(_firstChargeDate)} '
                      '(one month after payment date)',
                  color: Colors.white54,
                  fontsize: 12,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorAppBar,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      _infoRow('Frequency', 'Monthly'),
                      const SizedBox(height: 6),
                      _infoRow('Cycles', 'Ongoing until cancelled'),
                      const SizedBox(height: 6),
                      _infoRow(
                        'Monthly amount',
                        _money.format(monthly),
                        highlight: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _acceptedTerms,
                  activeColor: colorOrange,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const MyText(
                    text:
                        'I agree to a recurring monthly subscription charged to my card until cancelled',
                    color: Colors.white70,
                    fontsize: 13,
                  ),
                  onChanged: (v) =>
                      setState(() => _acceptedTerms = v ?? false),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorOrange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _continue(cart),
                  child: const Text(
                    'Continue to delivery',
                    style: TextStyle(
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

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Row(
      children: [
        MyText(text: label, color: Colors.white70, fontsize: 13),
        const Spacer(),
        MyText(
          text: value,
          color: highlight ? colorOrange : Colors.white,
          fontsize: highlight ? 15 : 13,
        ),
      ],
    );
  }
}
