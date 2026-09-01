import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalDocumentsPage extends StatelessWidget {
  const LegalDocumentsPage({super.key});

  Future<void> _open(BuildContext context, String url, String label) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      MyGlobalMessage.show(
        label,
        'Could not open the link.',
        MyMessageType.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle('Legal Documents'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: MyText(
              text: 'Official Limitless IOT policies and account documents.',
              color: Colors.white70,
              fontsize: 14,
            ),
          ),
          _LegalTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How we collect, use, and protect your data',
            onTap: () => _open(context, privacyPolicyUrl, 'Privacy Policy'),
          ),
          const SizedBox(height: 10),
          _LegalTile(
            icon: Icons.description_outlined,
            title: 'Terms and Conditions',
            subtitle: 'Sale, supply, use and support of our products',
            onTap: () =>
                _open(context, termsAndConditionsUrl, 'Terms and Conditions'),
          ),
          const SizedBox(height: 10),
          _LegalTile(
            icon: Icons.verified_outlined,
            title: 'Warranty and Returns',
            subtitle: '2-month refund and 2-year hardware warranty',
            onTap: () => _open(
              context,
              warrantyAndReturnsUrl,
              'Warranty and Returns',
            ),
          ),
          const SizedBox(height: 10),
          _LegalTile(
            icon: Icons.local_shipping_outlined,
            title: 'Shipping Policy',
            subtitle: 'Delivery areas, costs, times, and warranty returns',
            onTap: () => _open(context, shippingPolicyUrl, 'Shipping Policy'),
          ),
        ],
      ),
    );
  }
}

class _LegalTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LegalTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorTile,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: colorBlue, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MyText(
                      text: title,
                      color: Colors.white,
                      fontsize: 16,
                    ),
                    const SizedBox(height: 4),
                    MyText(
                      text: subtitle,
                      color: Colors.white54,
                      fontsize: 13,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, color: Colors.white38, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
