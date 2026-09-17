import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/shop_product_image.dart';
import 'package:geofence/shop_subscribe_page.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Confirms monthly subscriptions before delivery / payment details.
class ShopSubscriptionPage extends StatelessWidget {
  const ShopSubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
    return Consumer<ShopCartService>(
      builder: (context, cart, _) {
        final subItems = cart.items
            .where((i) => i.product.subscriptionMonthly > 0)
            .toList();
        final monthly = cart.subscriptionMonthlyTotal;

        return Scaffold(
          backgroundColor: colorAppBackground,
          appBar: AppBar(
            backgroundColor: colorAppBar,
            foregroundColor: Colors.white,
            title: myAppbarTitle('Subscription'),
          ),
          body: cart.isEmpty || subItems.isEmpty
              ? const Center(
                  child: MyText(
                    text: 'No subscription items in your basket',
                    color: Colors.white54,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorAppBar,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MyText(
                            text: 'Monthly subscription',
                            color: Colors.white,
                            fontsize: 18,
                          ),
                          SizedBox(height: 8),
                          MyText(
                            text:
                                'These items include a monthly subscription. '
                                'You will confirm it during payment. '
                                'The first charge is one month after the selected subscription payment date. '
                                'Subscription can be cancelled at any time.',
                            color: Colors.white70,
                            fontsize: 14,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final item in subItems) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorAppBar,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: ShopProductImage(
                                  imageUrl: item.product.primaryImageUrl,
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
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.quantity > 1
                                        ? '${item.quantity} × ${money.format(item.product.subscriptionMonthly)}/mo'
                                        : '${money.format(item.product.subscriptionMonthly)}/mo',
                                    style: const TextStyle(
                                      color: colorOrange,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              money.format(
                                item.product.subscriptionMonthly *
                                    item.quantity,
                              ),
                              style: const TextStyle(
                                color: colorIceBlue,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(color: Colors.white24),
                    Row(
                      children: [
                        const MyText(
                          text: 'Total monthly',
                          color: Colors.white,
                          fontsize: 16,
                        ),
                        const Spacer(),
                        MyText(
                          text: '${money.format(monthly)}/mo',
                          color: colorOrange,
                          fontsize: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    MyText(
                      text:
                          'First charge: one month after the selected subscription payment date',
                      color: Colors.white54,
                      fontsize: 12,
                    ),
                  ],
                ),
          bottomNavigationBar: cart.isEmpty || subItems.isEmpty
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
                        onPressed: () {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            MyGlobalMessage.show(
                              'Login required',
                              'Please log in to continue.',
                              MyMessageType.warning,
                            );
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ShopSubscribePage(),
                            ),
                          );
                        },
                        child: const Text(
                          'Continue Subscription',
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
}
