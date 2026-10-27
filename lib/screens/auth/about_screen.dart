// FILE: screens/auth/about_screen.dart
// SCREEN: About — app info and links.

import 'package:flutter/material.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'register_screen.dart';

/// SCREEN: About — app info and links.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  /// UI piece: point.
  Widget _point(IconData icon, String title, String body, {bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AiraColors.hair)),
      ),
      child: Row(
        children: [
          SunndariIconBubble(icon: icon, size: 58),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AiraText.serif(fontSize: 17)),
                const SizedBox(height: 3),
                Text(body, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: SunndariFlowBar(title: 'About Sunndari', onBack: () => Navigator.of(context).pop()),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
                  child: Column(
                    children: [
                      const SunndariLogo(width: 190),
                      const SizedBox(height: 18),
                      const SunndariTitle(
                        title: 'From Makeup Artist\nTo Beauty Entrepreneur.',
                        size: 28,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sunndari Helps Makeup Artists Showcase Their Talent, Connect With Clients And Build Their Own Beauty Business.',
                        textAlign: TextAlign.center,
                        style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft, height: 1.5),
                      ),
                      const SizedBox(height: 14),
                      _point(Icons.badge_outlined, 'Your Own Artist Page', 'Showcase Your Portfolio, Services And Pricing.'),
                      _point(Icons.groups_2_outlined, 'More Opportunities', 'Reach Clients Looking For Your Talent.'),
                      _point(Icons.trending_up_rounded, 'A Stronger Business',
                          'Manage Bookings And Grow Your Professional Presence.',
                          last: true),
                      const SizedBox(height: 30),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: AiraGradients.button,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Your Talent. Your Business. Your Sunndari.',
                          textAlign: TextAlign.center,
                          style: AiraText.serif(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
                child: PrimaryButton(
                  label: 'Proceed',
                  arrow: true,
                  expand: true,
                  // Navigates to RegisterScreen
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
